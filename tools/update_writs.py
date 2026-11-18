#!/usr/bin/env python3
"""Check a public Forever dataset and add only independently corroborated new rows.

No remote code is executed. Existing rows are never removed or changed. A failed
check leaves the addon untouched. It is safe to run while WoW is open; changes
are read by the game on its next reload.
"""
import argparse
import datetime as dt
import html.parser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
ADDON = Path.home()/'.local/share/Steam/steamapps/compatdata/3876850051/pfx/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/WritHelper'
STATE = Path.home()/'.local/state/writhelper/data-update.json'
SOURCE = 'https://raw.githubusercontent.com/AidVir/wow-forever-favor/main/data/writs.js'
ITEM_URL = 'https://db.icy-veins.com/wow-forever/items/{}'
ROW = re.compile(r'\[(\d{6}),\s*(AL|BS|EN|LW|TA),\s*([JEA]),\s*(\d+),\s*(\d+),\s*(\d+)(?:,\s*"(Alliance|Horde)")?\]')
LOCAL = re.compile(r'\{writ=(\d+),\s*item=(\d+),\s*count=(\d+),\s*rep=(\d+)\}')
PROF = {'AL':'alchemy','BS':'blacksmith','EN':'engineering','LW':'leatherworking','TA':'tailoring'}
REP = {'J':75,'E':125,'A':200}

class TextExtractor(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts=[]
        self.hidden=0
    def handle_starttag(self,tag,attrs):
        if tag in ('script','style'): self.hidden+=1
    def handle_endtag(self,tag):
        if tag in ('script','style') and self.hidden: self.hidden-=1
    def handle_data(self,data):
        if not self.hidden: self.parts.append(data)

def fetch(url):
    req=urllib.request.Request(url,headers={'User-Agent':'WritHelper-data-check/1.0'})
    with urllib.request.urlopen(req,timeout=15) as response:
        return response.read(3_000_000).decode('utf-8')

def parse_source(text):
    if 'export const WRITS' not in text:
        raise ValueError('Source is not the expected writ dataset')
    rows={}
    for m in ROW.finditer(text):
        wid,prof,rank,item,count,skill,side=m.groups()
        wid,item,count=int(wid),int(item),int(count)
        if wid in rows or not (100000<=wid<=999999 and 1<=item<=9999999 and 1<=count<=10000):
            raise ValueError('Duplicate or invalid row')
        rows[wid]={'writ':wid,'item':item,'count':count,'rep':REP[rank], 'profession':PROF[prof], 'side':side}
    if not 100<=len(rows)<=1000:
        raise ValueError('Unexpected number of source rows: '+str(len(rows)))
    return rows

def parse_local(text):
    rows={}
    for m in LOCAL.finditer(text):
        wid,item,count,rep=map(int,m.groups())
        if wid in rows: raise ValueError('Duplicate local writ '+str(wid))
        rows[wid]={'writ':wid,'item':item,'count':count,'rep':rep}
    if len(rows)<100: raise ValueError('Unexpected local database size')
    return rows

def second_source_confirms(item,quest,fixture_dir=None):
    html=(fixture_dir/('item-'+str(item)+'.html')).read_text(encoding='utf-8') if fixture_dir else fetch(ITEM_URL.format(item))
    parser=TextExtractor(); parser.feed(html)
    text=' '.join(parser.parts)
    # Require a nearby quest ID and a writ description, not just unrelated numbers.
    return bool(re.search(r"(?:Craftsman.{0,120}\b"+str(quest)+r"\b|\b"+str(quest)+r"\b.{0,120}Craftsman)",text,re.I|re.S))

def insert_before_close(text, additions):
    lines=text.splitlines()
    ends=[i for i,line in enumerate(lines) if line.strip()=='}']
    if len(ends)!=1: raise ValueError('Unexpected Lua database structure')
    lines[ends[0]:ends[0]]=additions
    return '\n'.join(lines)+'\n'

def save_atomic(path,text):
    tmp=path.with_name(path.name+'.updating')
    try:
        tmp.write_text(text,encoding='utf-8')
        os.replace(tmp,path)
    finally:
        if tmp.exists(): tmp.unlink()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--apply-verified',action='store_true')
    ap.add_argument('--source-file',type=Path,help='Offline source for testing')
    ap.add_argument('--verify-dir',type=Path,help='Offline verifier fixtures for testing')
    ap.add_argument('--root',type=Path,default=ROOT,help=argparse.SUPPRESS)
    ap.add_argument('--addon',type=Path,default=ADDON,help=argparse.SUPPRESS)
    ap.add_argument('--report',type=Path,default=STATE,help=argparse.SUPPRESS)
    args=ap.parse_args()
    report={'checked_at':dt.datetime.now(dt.timezone.utc).isoformat(),'source':SOURCE,'verification':'https://db.icy-veins.com/wow-forever/', 'applied':[], 'pending':[], 'conflicts':[], 'errors':[]}
    try:
        db_path=args.root/'Data.lua'; prof_path=args.root/'Professions.lua'
        db=db_path.read_text(encoding='utf-8'); prof=prof_path.read_text(encoding='utf-8')
        local=parse_local(db)
        remote=parse_source(args.source_file.read_text(encoding='utf-8') if args.source_file else fetch(SOURCE))
        report.update(local_count=len(local),source_count=len(remote))
        for wid,old in local.items():
            other=remote.get(wid)
            if other is None or any(old[k]!=other[k] for k in ('item','count','rep')):
                report['conflicts'].append({'writ':wid,'local':old,'source':other})
        for wid in sorted(set(remote)-set(local)):
            item=remote[wid]
            quest=94004 if wid == 264011 else wid-169800
            try:
                verified=quest>0 and second_source_confirms(item['item'],quest,args.verify_dir) and second_source_confirms(wid,quest,args.verify_dir)
            except (OSError,ValueError,urllib.error.URLError) as exc:
                verified=False; item=dict(item,verification_error=str(exc))
            (report['applied'] if verified and args.apply_verified else report['pending']).append(dict(item,verified=bool(verified)))
        if report['conflicts'] and report['applied']:
            report['pending'].extend(report['applied']); report['applied']=[]
            report['errors'].append('Conflicting existing records; automatic changes stopped')
        if report['applied']:
            # Never overwrite a game installation modified independently.
            for name,current in [('Data.lua',db),('Professions.lua',prof)]:
                if not (args.addon/name).is_file() or (args.addon/name).read_text(encoding='utf-8')!=current:
                    raise ValueError('Installed '+name+' differs from project; automatic update stopped')
            new_data=insert_before_close(db,[f"  {{writ={x['writ']}, item={x['item']}, count={x['count']}, rep={x['rep']}}}, -- checked automatically" for x in report['applied']])
            new_prof=insert_before_close(prof,[f"  [{x['writ']}] = {{{x['profession']}=true}}," for x in report['applied']])
            backup=args.root/'backups'/dt.datetime.now().strftime('data-%Y%m%d-%H%M%S')
            backup.mkdir(parents=True,exist_ok=False)
            (backup/'Data.lua').write_text(db,encoding='utf-8'); (backup/'Professions.lua').write_text(prof,encoding='utf-8')
            # Profession metadata is installed first; an interruption cannot leave an order without it.
            for name,text in [('Professions.lua',new_prof),('Data.lua',new_data)]:
                save_atomic(args.root/name,text); save_atomic(args.addon/name,text)
            report['local_count_after']=len(local)+len(report['applied'])
    except (OSError,ValueError,urllib.error.URLError) as exc:
        report['errors'].append(str(exc)); report['pending'].extend(report['applied']); report['applied']=[]
    args.report.parent.mkdir(parents=True,exist_ok=True)
    save_atomic(args.report,json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))
    if args.apply_verified and not args.source_file and (report['applied'] or report['conflicts']):
        notify=shutil.which('notify-send')
        if notify:
            message=('Добавлено заказов: '+str(len(report['applied']))+'. Перезагрузите интерфейс WoW.' if report['applied'] else 'Обнаружены расхождения. Существующие данные не изменены.')
            try: subprocess.run([notify,'WritHelper',message],check=False,timeout=5,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            except (OSError,subprocess.TimeoutExpired): pass
    return 1 if report['errors'] else 0

if __name__=='__main__':
    sys.exit(main())
