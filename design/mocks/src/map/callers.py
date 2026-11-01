"""Round eleven: how the Map says these are the row's callers.

tasksOf in raf (packages/core/src/run/tasks.ts:16), its four callers and
the lines that call it, as `make view` showed them on 2026-11-01. Writes
callers.html beside this file; `«cls|text»` is a coloured piece.
Run: python3 design/mocks/src/map/callers.py
"""
import html, os, re

CENTRE = '«d|(readonly »«t|ChecklistGroup»«d|[])» «d|→» «b|tasksOf» «d|→» readonly «t|DefinedTask»[]'

DESIGNS = [
    ('A', 'Now',
     'The line leaves what tasksOf gives and falls into heads that are what each caller gives. It reads as four more outputs.',
     f'''{CENTRE}
«l|                                        │»
«l|  ┌─────────────────────────────────────┘»
«l|  │»
«l|  ├─» «t|RunState»
«l|  │»    tasks.ts«d|:133»   «f|finish»            «d|(»«t|RunState»«d|,» «t|RunState»«d|)»
«l|  │»
«l|  ├─» readonly «t|Effect»[]
«l|  │»    update.ts«d|:82»   «f|checklistEvents»   «d|(»«t|Ran»«d|,» «t|Given»«d|,» «t|Views»«d|)»
«l|  │»
«l|  ├─» «t|string» | «t|null»
«l|  │»    tasks.ts«d|:35»    «f|taskIdFor»         «d|(readonly »«t|ChecklistGroup»«d|[], string)»
«l|  │»
«l|  └─» «d|nothing»
       tasks.ts«d|:101»   «f|conditions»        «d|(runState, change)»'''),
    ('B', 'Up into the name',
     'The line rises into tasksOf with ▲, never touching what it gives; the callers by folder, each with its whole signature, its own → on its line.',
     f'''{CENTRE}
«l|                                 ▲»
«l|  ┌──────────────────────────────┘»
«l|  │»
«l|  └─» «k|run/»
       tasks.ts«d|:35»    «f|taskIdFor»         «d|(readonly »«t|ChecklistGroup»«d|[], string)»   «d|→»  «t|string» | «t|null»
               «d|:101»   «f|conditions»        «d|(runState, change)»   «d|nothing»
               «d|:133»   «f|finish»            «d|(»«t|RunState»«d|,» «t|RunState»«d|)»   «d|→»  «t|RunState»
       update.ts«d|:82»   «f|checklistEvents»   «d|(»«t|Ran»«d|,» «t|Given»«d|,» «t|Views»«d|)»   «d|→»  readonly «t|Effect»[]'''),
    ('C', 'The call itself',
     'As B, but under each caller the line that calls it, copied in its colours, tasksOf lit in every one: you see them calling it, and what they do with what it gives.',
     f'''{CENTRE}
«l|                                 ▲»
«l|  ┌──────────────────────────────┘»
«l|  │»
«l|  ├─» «f|taskIdFor»         tasks.ts«d|:35»
«l|  │»    «B|tasksOf»(groups).«f|find»((task) «k|=>» task.walkthrough?.id «k|===» walkthrough)?.id «k|??» «k|null»;
«l|  │»
«l|  ├─» «f|conditions»        tasks.ts«d|:101»
«l|  │»    «k|const» open «k|=» «B|tasksOf»(runState.walkthroughsAndChecklistsInUse.checklistDefinitions).«f|filter»(
«l|  │»
«l|  ├─» «f|finish»            tasks.ts«d|:133»
«l|  │»    «k|for» («k|const» task «k|of» moved «k|?» «B|tasksOf»(after.walkthroughsAndChecklistsInUse.checklistDefinitions) «k|:» []) {{
«l|  │»
«l|  └─» «f|checklistEvents»   update.ts«d|:82»
       «k|for» («k|const» event «k|of» «f|eventsBetween»(«B|tasksOf»(after.walkthroughsAndChecklistsInUse.checklistDefinitions),
         announcedFrom, now, credit)) {{'''),
    ('D', 'Callers on top',
     'Top to bottom is who calls whom: its callers flow down into tasksOf, what it calls hangs below. Every arrow means calls; the calls lose their place above.',
     f'''«l|  ┌─» «k|run/»
«l|  │»    tasks.ts«d|:35»    «f|taskIdFor»         «d|(readonly »«t|ChecklistGroup»«d|[], string)»   «d|→»  «t|string» | «t|null»
«l|  │»            «d|:101»   «f|conditions»        «d|(runState, change)»   «d|nothing»
«l|  │»            «d|:133»   «f|finish»            «d|(»«t|RunState»«d|,» «t|RunState»«d|)»   «d|→»  «t|RunState»
«l|  │»    update.ts«d|:82»   «f|checklistEvents»   «d|(»«t|Ran»«d|,» «t|Given»«d|,» «t|Views»«d|)»   «d|→»  readonly «t|Effect»[]
«l|  │»
«l|  └──────────────────────────────┐»
«l|                                 ▼»
{CENTRE}
«d|                                 calls nothing»'''),
    ('E', 'Names on one line',
     'Under the name, its callers as names only, by file; their signatures and the line that calls it in the foot. Least to read.',
     f'''{CENTRE}
«l|                                 ▲»
«l|                                 └──» tasks.ts  «f|taskIdFor»  «f|conditions»  «f|finish»     update.ts  «f|checklistEvents»'''),
    ('F', 'Callers on the left',
     'The Map as it began: callers left of the row, a line from each into it, as reading goes. The calls stay above.',
     f'''«f|taskIdFor»        «d|tasks.ts:35»   «l|─┐»
«f|conditions»       «d|tasks.ts:101»  «l|─┤»
«f|finish»           «d|tasks.ts:133»  «l|─┼─▶» «b|tasksOf» «d|→» readonly «t|DefinedTask»[]
«f|checklistEvents»  «d|update.ts:82»  «l|─┘»
                                    «d|takes (readonly »«t|ChecklistGroup»«d|[])»'''),
]

def piece(m):
    cls, text = m.group(1), m.group(2)
    return f'<span class="{cls}">{html.escape(text)}</span>'

def render(src):
    out = []
    for part in re.split(r'(«[a-zA-Z]+\|[^»]*»)', src):
        m = re.fullmatch(r'«([a-zA-Z]+)\|([^»]*)»', part)
        out.append(piece(m) if m else html.escape(part))
    return ''.join(out)

CSS = '''
:root { color-scheme: dark; }
.page { display: flex; flex-direction: column; gap: 22px; font-family: var(--font-sans, sans-serif); }
.card h3 { margin: 0 0 4px; font-size: 14px; }
.card p { margin: 0 0 8px; font-size: 12.5px; color: var(--muted-foreground, #9aa); max-width: 680px; }
pre { margin: 0; padding: 16px; border-radius: var(--radius, 8px); background: #1a1b26; color: #c0caf5;
  font: 10.4px/1.55 var(--font-mono, monospace); overflow-x: auto; }
.d { color: #565f89; } .t { color: #2ac3de; } .f { color: #7dcfff; } .l { color: #545c7e; }
.b { color: #7aa2f7; font-weight: 700; } .B { color: #7aa2f7; font-weight: 700; text-decoration: underline; }
.k { color: #bb9af7; }
'''

def page():
    cards = ''.join(
        f'<div class="card"><h3>{k}. {html.escape(t)}</h3><p>{html.escape(d)}</p><pre>{render(src)}</pre></div>'
        for k, t, d, src in DESIGNS)
    return f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body><div class="page">{cards}</div></body></html>'

if __name__ == '__main__':
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'callers.html')
    open(out, 'w').write(page())
    print(out)
