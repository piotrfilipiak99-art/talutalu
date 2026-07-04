"""Deterministic morphological annotation via UDPipe 1 (C++ core).

Replaces LLM tokenization for supported languages: the parser tokenizes,
lemmatizes and tags with full UD features, deterministically, in
milliseconds, with exact character offsets — the three things LLMs proved
unreliable at (see project A/B tests). The LLM keeps the jobs it is good
at: writing the prose and glossing words (done in ai.py).

Models are ~25 MB on disk, ~100-200 MB in RAM each; an LRU keeps at most
UDPIPE_MAX_LOADED (default 2) in memory so this fits Render's 512 MB
Hobby instance next to FastAPI.
"""
import os
import threading
from collections import OrderedDict

import httpx
from ufal.udpipe import Model, Pipeline

# Our language codes -> UD 2.5 treebank names (one canonical pick each).
TREEBANKS = {
    'pl': 'polish-pdb', 'en': 'english-ewt', 'es': 'spanish-gsd',
    'fr': 'french-gsd', 'de': 'german-gsd', 'it': 'italian-isdt',
    'pt': 'portuguese-gsd', 'ru': 'russian-syntagrus', 'uk': 'ukrainian-iu',
    'ja': 'japanese-gsd', 'ko': 'korean-gsd', 'zh': 'chinese-gsdsimp',
    'ar': 'arabic-padt', 'nl': 'dutch-alpino', 'sv': 'swedish-talbanken',
    'tr': 'turkish-imst', 'cs': 'czech-pdt', 'el': 'greek-gdt',
    'hi': 'hindi-hdtb',
}

_MIRROR = ('https://raw.githubusercontent.com/jwijffels/udpipe.models.ud.2.5/'
           'master/inst/udpipe-ud-2.5-191206/{tb}-ud-2.5-191206.udpipe')

MODELS_DIR = os.environ.get(
    'UDPIPE_MODELS_DIR',
    os.path.join(os.path.dirname(os.path.abspath(__file__)), 'udpipe_models'))
MAX_LOADED = int(os.environ.get('UDPIPE_MAX_LOADED', '2'))

_loaded: 'OrderedDict[str, Model]' = OrderedDict()
_lock = threading.Lock()


def supported(lang: str) -> bool:
    return lang in TREEBANKS


def _model_path(lang: str) -> str:
    return os.path.join(MODELS_DIR, f'{TREEBANKS[lang]}.udpipe')


def _download(lang: str) -> str:
    path = _model_path(lang)
    if os.path.exists(path):
        return path
    os.makedirs(MODELS_DIR, exist_ok=True)
    url = _MIRROR.format(tb=TREEBANKS[lang])
    tmp = path + '.part'
    with httpx.stream('GET', url, follow_redirects=True, timeout=120) as r:
        r.raise_for_status()
        with open(tmp, 'wb') as f:
            for chunk in r.iter_bytes():
                f.write(chunk)
    os.replace(tmp, path)
    return path


def _get_model(lang: str) -> Model:
    with _lock:
        if lang in _loaded:
            _loaded.move_to_end(lang)
            return _loaded[lang]
    path = _download(lang)
    model = Model.load(path)
    if model is None:
        raise RuntimeError(f'UDPipe model failed to load: {path}')
    with _lock:
        _loaded[lang] = model
        _loaded.move_to_end(lang)
        while len(_loaded) > MAX_LOADED:
            _loaded.popitem(last=False)  # evict least recently used
    return model


def _parse_feats(feats: str) -> dict:
    if not feats or feats == '_':
        return {}
    out = {}
    for part in feats.split('|'):
        if '=' in part:
            k, v = part.split('=', 1)
            out[k] = v
    return out


def _token_range(misc: str):
    for part in (misc or '').split('|'):
        if part.startswith('TokenRange='):
            a, b = part[len('TokenRange='):].split(':')
            return int(a), int(b)
    return None


def _merge_words(words: list[dict]) -> dict:
    """One app token from a multiword token (e.g. 'spakowałem' =
    'spakował' VERB + 'em' AUX): the first non-auxiliary word provides
    lemma/POS, features merge across parts (first occurrence wins), so the
    clitic contributes Person/Number the content word lacks."""
    rep = next((w for w in words if w['upos'] not in ('AUX', 'PART')),
               words[0])
    feats = dict(rep['feats'])
    for w in words:
        for k, v in w['feats'].items():
            feats.setdefault(k, v)
    return {'lemma': rep['lemma'], 'upos': rep['upos'], 'feats': feats}


def annotate_sentence(text: str, lang: str) -> list[dict]:
    """Tokens for one sentence: [{surface, lemma, pos, morph, start, end}]
    with offsets in Unicode characters relative to [text]."""
    model = _get_model(lang)
    # 'tokenizer=ranges' (not 'tokenize;ranges') — the option must be given
    # as the tokenizer spec, and it puts TokenRange=a:b into MISC.
    pipe = Pipeline(model, 'tokenizer=ranges', Pipeline.DEFAULT,
                    Pipeline.NONE, 'conllu')
    conllu = pipe.process(text)
    if not conllu:
        raise RuntimeError('UDPipe produced no output')

    tokens = []
    pending_mwt = None  # (surface, start, end, last_word_id, words)
    for line in conllu.splitlines():
        if not line or line.startswith('#'):
            continue
        cols = line.split('\t')
        wid, form, lemma, upos, feats, misc = (
            cols[0], cols[1], cols[2], cols[3], cols[5], cols[9])
        if '.' in wid:
            continue  # empty nodes
        if '-' in wid:
            rng = _token_range(misc)
            if rng is None:
                continue
            last = int(wid.split('-')[1])
            pending_mwt = (form, rng[0], rng[1], last, [])
            continue
        word = {'lemma': lemma, 'upos': upos, 'feats': _parse_feats(feats)}
        if pending_mwt is not None:
            surface, start, end, last, words = pending_mwt
            words.append(word)
            if int(wid) >= last:
                merged = _merge_words(words)
                tokens.append({'surface': surface, 'lemma': merged['lemma'],
                               'pos': merged['upos'],
                               'morph': merged['feats'],
                               'start': start, 'end': end})
                pending_mwt = None
            continue
        rng = _token_range(misc)
        if rng is None:
            continue
        tokens.append({'surface': form, 'lemma': lemma, 'pos': upos,
                       'morph': word['feats'],
                       'start': rng[0], 'end': rng[1]})
    return tokens


def annotate_sentences(body: str, sentence_spans: list[dict],
                       lang: str) -> list[dict]:
    """App-shaped tokens (charStart/charEnd absolute in [body],
    sentenceIndex from the given spans), glosses left as None for the LLM
    to fill in. root/rootMeaning stay None per project policy (dictionary
    grounding pending)."""
    out = []
    for span in sentence_spans:
        seg = body[span['charStart']:span['charEnd']]
        for t in annotate_sentence(seg, lang):
            out.append({
                'surface': t['surface'],
                'lemma': t['lemma'],
                'translation': None,
                'lemmaTranslation': None,
                'pos': t['pos'],
                'morph': t['morph'],
                'reading': None,
                'root': None,
                'rootMeaning': None,
                'sentenceIndex': span['index'],
                'charStart': span['charStart'] + t['start'],
                'charEnd': span['charStart'] + t['end'],
            })
    return out
