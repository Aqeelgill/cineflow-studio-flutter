#!/usr/bin/env python3
import argparse, csv, json, re, sys, urllib.parse
from html.parser import HTMLParser

MEDIA_EXTS = {'.mp4','.mkv','.avi','.mov','.wmv','.flv','.webm','.m4v','.ts','.m3u8','.mpd','.mp3','.m4a','.aac','.flac','.wav','.ogg'}
MEDIA_KEYWORDS = ['dual audio','multi audio','1080p','720p','480p','2160p','4k','web-dl','hdrip','bluray','x264','x265','hevc','hindi','urdu','dubbed','season','episode']
VIDEO_HOSTS = ['youtube.com','youtu.be','dailymotion.com','facebook.com','fb.watch','vimeo.com']
NON_MEDIA_EXTS = {'.jpg','.jpeg','.png','.gif','.webp','.css','.js','.svg','.ico','.woff','.woff2','.ttf'}

class LinkHTML(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links=[]
        self._text=[]
    def handle_starttag(self, tag, attrs):
        a=dict(attrs)
        for k in ('href','src','data-src','content'):
            v=a.get(k)
            if v: self.links.append(v)
    def handle_data(self,data):
        if data and data.strip(): self._text.append(data.strip())

def walk(obj, out):
    if isinstance(obj, dict):
        for k,v in obj.items():
            if isinstance(v,(dict,list)): walk(v,out)
            elif isinstance(v,str): out.append((str(k),v))
    elif isinstance(obj, list):
        for v in obj: walk(v,out)

def is_media_url(url, hint=''):
    try:
        u=url.strip()
        if not re.match(r'^https?://',u,re.I): return False
        p=urllib.parse.urlparse(u)
        path=p.path.lower()
        host=p.netloc.lower()
        low=(u+' '+hint).lower()
        if any(path.endswith(ext) for ext in NON_MEDIA_EXTS): return False
        if any(path.endswith(ext) for ext in MEDIA_EXTS): return True
        if any(k in low for k in MEDIA_KEYWORDS): return True
        if any(h in host for h in VIDEO_HOSTS) and ('watch' in low or 'video' in low or 'youtu.be' in host or '/v/' in path):
            return True
        if any(h in host for h in VIDEO_HOSTS) and re.search(r'(mp4|mkv|mp3|m3u8|mpd)',low):
            return True
        # common direct movie file links not ending cleanly
        if re.search(r'\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|ts|m3u8|mpd|mp3|m4a|aac|flac|wav|ogg)(\?|$)',low):
            return True
        return False
    except Exception:
        return False

def detect_format(url):
    p=urllib.parse.urlparse(url)
    ext=os_ext(p.path.lower())
    return ext.upper().lstrip('.') if ext else 'MEDIA'

def os_ext(path):
    for e in MEDIA_EXTS:
        if path.endswith(e): return e
    m=re.search(r'\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|ts|m3u8|mpd|mp3|m4a|aac|flac|wav|ogg)',path,re.I)
    return '.'+m.group(1).lower() if m else ''

def detect_tag(text):
    low=text.lower(); tags=[]
    if 'dual audio' in low: tags.append('Dual Audio')
    elif 'multi audio' in low: tags.append('Multi Audio')
    if '2160p' in low or '4k' in low: tags.append('4K')
    elif '1080p' in low: tags.append('1080p')
    elif '720p' in low: tags.append('720p')
    if 'dubbed' in low and 'Dubbed' not in tags: tags.append('Dubbed')
    return ' / '.join(tags)

def title_from_url(url, hint=''):
    base=hint.strip() or urllib.parse.unquote(urllib.parse.urlparse(url).path.rsplit('/',1)[-1])
    base=re.sub(r'\.[A-Za-z0-9]{2,5}$','',base)
    base=re.sub(r'[_\-]+',' ',base).strip()
    return base or url

def extract_media(content, filename=''):
    items=[]; seen=set()
    def add(url,hint=''):
        u=url.strip().strip('"\'<>')
        if not is_media_url(u,hint): return
        if u in seen: return
        seen.add(u)
        fmt=detect_format(u)
        tag=detect_tag(u+' '+hint)
        items.append({'url':u,'title':title_from_url(u,hint),'format':fmt,'tag':tag})

    name=filename.lower()
    if name.endswith('.json'):
        try:
            obj=json.loads(content)
            pairs=[]; walk(obj,pairs)
            for k,v in pairs:
                if isinstance(v,str) and re.match(r'https?://',v.strip(),re.I):
                    add(v,k)
                elif isinstance(v,str):
                    for m in re.finditer(r'https?://[^\s"\']+',v):
                        add(m.group(0),k)
        except Exception:
            pass
    if name.endswith('.html') or name.endswith('.htm') or '<html' in content.lower():
        p=LinkHTML(); p.feed(content)
        for l in p.links: add(l)
        for t in p._text:
            for m in re.finditer(r'https?://[^\s"\']+',t): add(m.group(0),t)
    # generic URL scrape for txt/csv/xml/json fallback
    for m in re.finditer(r'https?://[^\s"\'<>\]\)]+', content):
        add(m.group(0))
    return items

def extract_leads(content, filename=''):
    leads=[]; seen=set()
    email_re=re.compile(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',re.I)
    phone_re=re.compile(r'(?:\+?\d[\d\s().-]{7,}\d)')
    url_re=re.compile(r'https?://[^\s"\'<>\]\)]+',re.I)
    social_hosts=['facebook.com','linkedin.com','twitter.com','x.com','instagram.com','youtube.com','tiktok.com']

    def norm_phone(p): return re.sub(r'\D','',p)
    def add(d):
        d={k:(d.get(k) or '').strip() for k in ['name','email','phone','website','social','category']}
        key=(d['email'].lower(),norm_phone(d['phone']),d['website'].lower(),d['social'].lower(),d['name'].lower())
        if not any(d.values()): return
        if all(not d[k] for k in ['email','phone','website','social','name']): return
        if key in seen: return
        seen.add(key)
        leads.append(d)

    name=filename.lower()
    if name.endswith('.json'):
        try:
            obj=json.loads(content)
            def walk_obj(x):
                if isinstance(x,dict):
                    # if dict looks like contact
                    keys={str(k).lower() for k in x.keys()}
                    if keys & {'email','phone','website','social','name','company','contact'}:
                        add({
                            'name': str(x.get('name') or x.get('company') or x.get('contact') or ''),
                            'email': str(x.get('email') or ''),
                            'phone': str(x.get('phone') or x.get('mobile') or ''),
                            'website': str(x.get('website') or x.get('url') or ''),
                            'social': str(x.get('social') or x.get('linkedin') or x.get('facebook') or ''),
                            'category': str(x.get('category') or x.get('niche') or '')
                        })
                    for v in x.values(): walk_obj(v)
                elif isinstance(x,list):
                    for v in x: walk_obj(v)
            walk_obj(obj)
        except Exception:
            pass

    # generic extraction
    for em in email_re.findall(content): add({'email':em})
    for ph in phone_re.findall(content):
        if len(norm_phone(ph))>=7: add({'phone':ph.strip()})
    for u in url_re.findall(content):
        ul=u.lower()
        if any(h in ul for h in social_hosts): add({'social':u})
        elif not any(ul.endswith(e) for e in NON_MEDIA_EXTS): add({'website':u})
    return [l for l in leads if any(l.values())]

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--mode', choices=['media','leads'], required=True)
    ap.add_argument('--file')
    ap.add_argument('--url')
    args=ap.parse_args()
    content=''
    filename=args.file or args.url or ''
    if args.file:
        with open(args.file,'r',encoding='utf-8',errors='ignore') as f: content=f.read()
    elif args.url:
        import urllib.request
        req=urllib.request.Request(args.url, headers={'User-Agent':'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=20) as r: content=r.read().decode('utf-8',errors='ignore')
        filename=args.url
    else:
        content=sys.stdin.read()
    if args.mode=='media':
        json.dump(extract_media(content,filename), sys.stdout)
    else:
        json.dump(extract_leads(content,filename), sys.stdout)

if __name__=='__main__':
    main()
