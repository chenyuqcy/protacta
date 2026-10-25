#!/usr/bin/env python3
"""Build an explicit 90-second edit from approved completed capture checkpoints.

Supply run01 first and the successful recapture run second. Later matching IDs
replace earlier ones. This writes JSON only; it never starts an encoder.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

FPS = 30


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--capture-manifest',type=Path,action='append',required=True)
    p.add_argument('--output',type=Path,default=Path(__file__).with_name('edit_manifest.json'))
    args=p.parse_args()
    clips={}
    for path in args.capture_manifest:
        data=json.loads(path.read_text())
        for c in data.get('clips',[]):
            if c.get('doneAt') and c.get('recorderExitCode')==0 and c.get('probe',{}).get('format',{}).get('duration'):
                clips[c['id']]=c
    required=['01_origami','02_everyday','03_aeris','04_synthetic_paper']
    missing=[name for name in required if name not in clips]
    if missing:raise SystemExit('Completed capture metadata missing: '+', '.join(missing))
    def event(clip_id,name):
        c=clips[clip_id]
        matches=[x for x in c['events'] if x['clipID']==clip_id and x['name']==name]
        if not matches:raise ValueError(f'Missing required checkpoint {clip_id}/{name}')
        return matches[-1]['timestamp']-c['firstFrameObservedAt']
    def has(clip_id,name):return any(x['clipID']==clip_id and x['name']==name for x in clips[clip_id]['events'])
    def cut(clip_id,start,duration,title,kicker,subtitle,scope,display_index,bullets=None):
        # Frame-quantize both endpoints while preserving the declared duration.
        start=round(start*FPS)/FPS;end=start+round(duration*FPS)/FPS
        source_duration=float(clips[clip_id]['probe']['format']['duration'])
        if start<0 or end>source_duration+.03:raise ValueError(f'Trim {clip_id} {start:.3f}..{end:.3f} outside {source_duration:.3f}s; inspect capture')
        return {'source':clips[clip_id]['source'],'start':round(start,6),'end':round(end,6),
                'title':title,'kicker':kicker,'subtitle':subtitle,'scope':scope,
                'display_index':display_index,'bullets':bullets or []}

    home=cut('01_origami',.5,5,'See it. Then do it.','One tutorial hub',
             'Step-by-step guidance, inside one native app.','native',1,
             ['Origami · everyday skills · product manuals'])
    fold=cut('01_origami',event('01_origami','center_crease_3d')-4,12,
             'See the movement.','Origami / 3D reference',
             'Pause, replay and change the view.','native',2,['Authored steps and learner controls'])
    help_cut=cut('01_origami',event('01_origami','written_fold_help')-3.5,7,
                 'Help when you need it.','Origami / step help',
                 'Read the explanation for the current action.','native',2)
    finish=cut('01_origami',event('01_origami','finished_dart_reference_not_physical_completion')+.2,4,
               'Preview the result.','Origami / target shape',
               'A rendered reference for the learner to compare.','native',2)
    shirt=cut('02_everyday',event('02_everyday','tshirt_start')+1,14,
              'From paper to everyday.','Everyday / T-shirt',
              'Follow the animated movement, then compare.','everyday',3,
              ['Start / Target references','Progress confirmed by the learner'])
    knot=cut('02_everyday',event('02_everyday','square_knot_illustration')+1,4,
             'Practice a square knot.','Everyday / knot reference',
             'Named ends make the sequence easier to follow.','everyday',3)
    tie=cut('02_everyday',event('02_everyday','tie_illustration')+.5,4,
            'Follow the tie.','Everyday / four-in-hand',
            'One shared player, different practical skills.','everyday',3)

    interaction=cut('03_aeris',event('03_aeris','release_interaction_gate')-.5,10,
                    'Interact with the parts.','AERIS / product manual',
                    'Press the highlighted tab before continuing.','aeris',4)
    # Only the observed exploded checkpoint permits an exploded-view caption.
    if has('03_aeris','exploded_product'):
        parts=cut('03_aeris',event('03_aeris','exploded_product')+.1,12,
                  'See how parts fit.','AERIS / explore parts',
                  'Move between assembly and exploded views.','aeris',4)
    else:
        parts=cut('03_aeris',event('03_aeris','rear_cover_open')-.5,12,
                  'Follow each product step.','AERIS / guided parts',
                  'Open the rear cover and inspect the filter.','aeris',4)

    aligned=cut('04_synthetic_paper',event('04_synthetic_paper','paper_aligned')-.8,4,
                'Guide. Hide. Recover.','Paper guidance / simulated states',
                'Confirm the direction before showing the guide.','synthetic',5)
    hidden=cut('04_synthetic_paper',event('04_synthetic_paper','paper_hidden')+.1,3,
               'Hide uncertain guidance.','Paper guidance / simulated loss',
               'The drawing disappears when correspondence is lost.','synthetic',5)
    recover=cut('04_synthetic_paper',event('04_synthetic_paper','synthetic_reconfirmed')-1.3,3,
                'Confirm before resuming.','Paper guidance / simulated return',
                'Reacquisition asks the learner to check direction.','synthetic',5)
    compare=cut('04_synthetic_paper',event('04_synthetic_paper','checkpoint_comparison')+.2,4,
                'Inspect one comparison.','Paper guidance / simulated checkpoint',
                'A frozen view with an outline and comparison areas.','synthetic',5)
    closing=cut('01_origami',.2,4,'Explore the prototype.','One app / many practical tasks',
                'Visual instructions. Learner-controlled practice.','native',6)
    chapters=[home,fold,help_cut,finish,shirt,knot,tie,interaction,parts,aligned,hidden,recover,compare,closing]
    assert sum(round((x['end']-x['start'])*FPS) for x in chapters)==90*FPS

    everyday_help=cut('02_everyday',event('02_everyday','action_specific_written_help')+.2,4,
                      'Help for this action.','Everyday / authored help',
                      'Written guidance and replay share the same action.','everyday',3)
    synthetic_start=event('04_synthetic_paper','synthetic_direction_needed')-.2
    synthetic_end=event('04_synthetic_paper','synthetic_reconfirmed')+2
    if 15 <= synthetic_end-synthetic_start+4 <= 30:
        continuous=cut('04_synthetic_paper',synthetic_start,synthetic_end-synthetic_start,
                       aligned['title'],aligned['kicker'],aligned['subtitle'],'synthetic',5)
        synthetic_segments=[continuous,compare]
    else:
        longer_aligned=dict(aligned,end=round(aligned['end']+1,6))
        longer_compare=dict(compare,end=round(compare['end']+1,6))
        synthetic_segments=[longer_aligned,hidden,recover,longer_compare]
    standalones=[
        {'name':'01_Origami_3D','segments':[fold,help_cut,finish]},
        {'name':'02_Everyday_Skills','segments':[shirt,everyday_help,knot,tie]},
        {'name':'03_AERIS_Manual','segments':[interaction,parts]},
        {'name':'04_Synthetic_Paper_Flow','segments':synthetic_segments}
    ]
    for s in standalones:
        duration=sum(round((x['end']-x['start'])*FPS)/FPS for x in s['segments'])
        if not 15<=duration<=30:raise ValueError(f'Standalone {s["name"]} is {duration}s, outside15..30')
        s['duration']=duration
    manifest={'source_provenance':'actual_ios_simulator_recordings',
              'source_capture_manifests':[str(x.resolve()) for x in args.capture_manifest],
              'edition':'Native prototype · Build 7','target_duration':90,
              'display_total_chapters':6,'chapters':chapters,'standalones':standalones,
              'physicalAcceptance':False,
              'editorialNote':'Explicit cuts from real simulator UI. Synthetic paper states remain strongly marked; AERIS is a virtual concept product. No physical alignment, camera accuracy, speech or learner result is claimed.'}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps({'manifest':str(args.output.resolve()),'mainDuration':90,
                      'sourceCuts':len(chapters),'editorialChapters':6,
                      'portraitDurations':{s['name']:s['duration'] for s in standalones},
                      'aerisExplodedCaptionUsed':has('03_aeris','exploded_product')},indent=2))


if __name__=='__main__':main()
