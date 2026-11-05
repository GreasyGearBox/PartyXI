"""Build PartyXI facts from Phoenix YAML, with module merge-patch order.

Uses Phoenix data and loader semantics directly; no other addon dependency.
Run with SOURCE OUTPUT arguments. PyYAML is a build-only dependency.
"""
from pathlib import Path
import sys, json, subprocess, copy
sys.path.insert(0, str(Path(__file__).parent/'vendor'))
import yaml
def read_yaml(path):
    return yaml.load(path.read_text(encoding='utf-8-sig'),Loader=yaml.CSafeLoader) or {}

def patch(base, change):
    if not isinstance(change, dict):
        return copy.deepcopy(change)
    out=copy.deepcopy(base) if isinstance(base,dict) else {}
    for k,v in change.items():
        if v is None: out.pop(k,None)
        else: out[k]=patch(out.get(k),v)
    return out

def module_roots(source):
    roots=[]
    for line in (source/'modules/init.txt').read_text().splitlines():
        entry=line.split('#',1)[0].strip()
        if not entry: continue
        parts=Path(entry).parts
        # Phoenix live 9a4494d505: moduleutils::GetDataModules keeps the first
        # occurrence of each top-level module, including SQL/Lua entries.
        # Explicit nested paths are not independent data roots in this revision.
        root=source/'modules'/parts[0]/'data'
        if root not in roots: roots.append(root)
    return roots

def merged(source, roots, relative):
    file=source/'data'/relative
    value=read_yaml(file) if file.exists() else {}
    for root in roots:
        file=root/relative
        if file.exists(): value=patch(value,read_yaml(file))
    return value

def lua(value):
    if isinstance(value,bool): return 'true' if value else 'false'
    if isinstance(value,(int,float)): return str(value)
    if isinstance(value,str): return json.dumps(value,ensure_ascii=False)
    if isinstance(value,list): return '{'+','.join(map(lua,value))+'}'
    if isinstance(value,dict): return '{'+','.join('['+lua(k)+']='+lua(v) for k,v in value.items())+'}'
    raise TypeError(value)

def normal(name): return name.replace('_',' ')

def build(source, output):
    roots=module_roots(source)
    ecosystems=merged(source,roots,'ecosystems.yaml')['ecosystems']
    species={}
    for e in ecosystems.values():
        for f in (e.get('families') or {}).values():
            inherited=patch(e.get('attributes',{}),f.get('attributes',{}))
            for name,s in (f.get('species') or {}).items():
                species[name]=patch(inherited,s.get('attributes',{}))
    zones=merged(source,roots,'enums/zone.yaml')['values']
    report={'revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=source,text=True).strip(),
            'modules':[str(r.relative_to(source)).replace('\\','/') for r in roots], 'zones':{},'skipped':{}}
    output.mkdir(parents=True,exist_ok=True)
    for zone,zid in zones.items():
        rel=f'zones/{zone}/mobs.yaml'
        if not (source/'data'/rel).exists(): continue
        doc=merged(source,roots,rel);templates=doc.get('templates') or {}
        template_aliases={}
        for spawn in (doc.get('spawns') or {}).values():
            if isinstance(spawn,dict) and spawn.get('template') and spawn.get('script'):
                template_aliases.setdefault(spawn['template'],set()).add(normal(spawn['script']))
        rows=[];ids={};names={};keys={}
        for sid,spawn in sorted((doc.get('spawns') or {}).items()):
            if not isinstance(sid,int) or not isinstance(spawn,dict): continue
            template=spawn.get('template');t=templates.get(template)
            # Like the server: reserved script-only or unplaced IDs are not static mobs.
            if not t or not any(spawn.get(k) is not None for k in ['at','region','path','circuit']): continue
            level=spawn.get('level')
            if not level or len(level)!=2 or not 0<level[0]<=level[1]:
                report['skipped'][str(sid)]='no static level';continue
            if t.get('species') not in species: raise ValueError((zone,template,'unknown species'))
            attrs=patch(patch(species[t['species']],t.get('attributes',{})),spawn.get('attributes',{}))
            behavior=attrs.get('behaviors') or {}
            methods=[]
            for flag,label in [('sight','Sight'),('hearing','Sound'),('lowhp','Low HP'),('magic','Magic'),('ability','Ability'),('scent','Scent')]:
                if flag in (attrs.get('detects') or []):
                    methods.append(('True ' if behavior.get('true_detection') and flag in ['sight','hearing'] else '')+label)
            internal=normal(t.get('display_name') or template)
            script=normal(spawn.get('script') or template)
            aliases=sorted(set([internal,script]) | template_aliases.get(template,set()))
            row={'name':internal,'min':level[0],'max':level[1],'aggro':bool(behavior.get('aggressive',False)),
                 'link':bool(behavior.get('links',False)),'methods':methods,'aliases':aliases}
            key=json.dumps(row,sort_keys=True)
            if key not in keys: keys[key]=len(rows)+1;rows.append(row)
            ids[sid]=keys[key]
        # Names are only a fallback when every matching record has identical facts.
        for i,row in enumerate(rows,1):
            for name in row['aliases']:
                names[name]=i if name not in names else (i if names[name]==i else False)
        names={n:i for n,i in names.items() if i is not False}
        data={'rows':rows,'ids':ids,'names':names}
        (output/f'{zid}.lua').write_text('-- Phoenix live snapshot; module patches applied in modules/init.txt order.\nreturn '+lua(data)+'\n',encoding='utf-8')
        report['zones'][str(zid)]={'name':zone,'spawns':len(ids),'rows':len(rows)}
    (output/'phoenix-source.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return report

if __name__=='__main__':
    result=build(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
    print('Built',len(result['zones']),'zones,',sum(z['spawns'] for z in result['zones'].values()),'spawns from',result['revision'])
