#!/usr/bin/env python3
"""Render typography only, using local bundled Pillow and installed Arial files."""
from __future__ import annotations
import argparse
import json
import math
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

FFMPEG='/opt/homebrew/bin/ffmpeg'
REGULAR='/System/Library/Fonts/Supplemental/Arial.ttf'
BOLD='/System/Library/Fonts/Supplemental/Arial Bold.ttf'
BG='#F1F0E9'; INK='#17392E'; MUTED='#5C6F65'; ACCENT='#A84829'


def font(size, bold=False): return ImageFont.truetype(BOLD if bold else REGULAR,size)


def wrapped(draw,text,face,width):
    lines=[]
    for paragraph in str(text).split('\n'):
        current=''
        for word in paragraph.split():
            attempt=(current+' '+word).strip()
            if current and draw.textlength(attempt,font=face)>width:
                lines.append(current);current=word
            else:current=attempt
        lines.append(current)
    return lines


def textblock(draw,text,xy,face,width,fill=INK,gap=9):
    x,y=xy
    for line in wrapped(draw,text,face,width):
        draw.text((x,y),line,font=face,fill=fill,anchor='lt')
        y+=face.size+gap
    return y


def tracking(draw,text,xy,face,fill,spacing=4):
    x,y=xy
    for char in text:
        draw.text((x,y),char,font=face,fill=fill,anchor='lt')
        x+=draw.textlength(char,font=face)+spacing


def scope_text(scope):
    return {'native':('NATIVE APP WALKTHROUGH','Authored 3D guidance and learner controls.'),
            'everyday':('ILLUSTRATED SKILLS','Animated reference · manual comparison'),
            'synthetic':('SYNTHETIC PAPER FIXTURE','Synthetic paper fixture · not live camera'),
            'aeris':('VIRTUAL CONCEPT PRODUCT','Virtual concept product · interactive 3D manual')}[scope]


def make_plate(item,spec):
    s=item['segment'];portrait=item['portrait'];x,y,w,h=item['geometry']
    W,H=(1080,1920) if portrait else (1920,1080)
    image=Image.new('RGB',(W,H),BG);d=ImageDraw.Draw(image)
    if portrait:
        image.paste(INK,(0,0,W,H));d=ImageDraw.Draw(image)
        caption='iOS Simulator · native prototype'
        d.text((W/2,16),caption,font=font(23),fill='#F1F0E9',anchor='mt')
        label=scope_text(s['scope'])[1]
        face=font(27,True)
        if s['scope']=='synthetic':
            textblock(d,'Synthetic paper fixture\nNot a live camera',(40,1840),face,1000,fill='#FFD69C',gap=5)
        else:
            lines=wrapped(d,label,face,1000)
            for i,line in enumerate(lines):d.text((W/2,1855+i*31),line,font=face,fill='#F1F0E9',anchor='mt')
        image.save(item['output']);return
    # An understated paper/ink treatment stays separate from the actual app UI.
    tracking(d,'PROTACTA',(92,70),font(25,True),INK,6)
    d.text((92,112),spec.get('edition','Native prototype · Build 7'),font=font(22),fill=MUTED,anchor='lt')
    wide=s['width']>s['height']
    left_width=590 if wide else 810
    display_index=s.get('display_index',s['index'])
    d.text((92,216),f"{display_index:02d} / {spec['total_chapters']:02d}   {s.get('kicker','TUTORIAL IN YOUR HANDS').upper()}",font=font(20,True),fill=ACCENT,anchor='lt')
    title_size=58 if wide else 72
    face=font(title_size,True)
    title_lines=wrapped(d,s['title'],face,left_width)
    if len(title_lines)>3:
        face=font(58,True);title_lines=wrapped(d,s['title'],face,left_width)
    title_y=268
    for line in title_lines:
        d.text((92,title_y),line,font=face,fill=INK,anchor='lt');title_y+=face.size+5
    body_y=max(463,title_y+42)
    if s.get('subtitle'):
        body_y=textblock(d,s['subtitle'],(96,body_y),font(31),left_width-20,fill=MUTED,gap=12)+28
    bullets=s.get('bullets',[])
    for line in bullets[:3]:
        d.ellipse((96,body_y+11,103,body_y+18),fill=ACCENT)
        body_y=textblock(d,line,(122,body_y),font(27),left_width-46,fill=INK,gap=9)+20
    if body_y > 770:
        raise ValueError(f'Chapter {s["index"]} captions are too long; shorten title/subtitle/bullets rather than overlap the scope label')
    # Never cover the app recording with text: all scope text occupies left rail.
    label,detail=scope_text(s['scope'])
    pill_y=796
    scope_width=left_width
    warning=s['scope']=='synthetic'
    d.rounded_rectangle((92,pill_y,92+scope_width,pill_y+134),radius=18,
                        fill='#F8E0B8' if warning else '#E3E7DD')
    d.text((116,pill_y+23),label,font=font(20,True),fill=ACCENT if warning else INK,anchor='lt')
    textblock(d,detail,(116,pill_y+61),font(25,warning),scope_width-48,fill=INK,gap=7)
    d.text((92,1004),'iOS Simulator · native prototype',font=font(23,True),fill=MUTED,anchor='lt')
    # Progress rules are editorial chapter indicators, not app controls.
    total=spec['total_chapters']; length=min(790,left_width); gap=9
    segment=(length-gap*(total-1))/total
    for i in range(total):
        a=92+i*(segment+gap)
        d.rounded_rectangle((a,965,a+segment,970),radius=2,fill=ACCENT if i+1==display_index else '#D1D8CC')
    # Soft framing uses only empty background around the captured pixels.
    for spread,fill in [(14,'#DADFD5'),(7,'#D2D9CE')]:
        d.rounded_rectangle((x-spread,y-spread,x+w+spread,y+h+spread),radius=25+spread,fill=fill)
    d.rounded_rectangle((x-2,y-2,x+w+2,y+h+2),radius=23,fill='#17392E')
    image.save(item['output'])


def contact(spec_path):
    spec=json.loads(spec_path.read_text());output=Path(spec['output']);folder=spec_path.parent/'qa_frames';folder.mkdir(exist_ok=True)
    captures=[]
    for item in spec['timeline']:
        duration=item['end']-item['start']
        for label,offset in [('start',min(.5,duration/8)),('middle',duration/2),('end',max(0,duration-.5))]:
            at=item['start']+offset;p=folder/f"chapter_{item['index']:02d}_{label}.png"
            subprocess.run([FFMPEG,'-hide_banner','-loglevel','error','-y','-ss',f'{at:.6f}','-i',str(output),'-frames:v','1',str(p)],check=True)
            captures.append((p,f"{at:05.1f}s · {item['index']:02d} · {label}"))
    columns=3;tile_w=480;tile_h=296;rows=math.ceil(len(captures)/columns)
    sheet=Image.new('RGB',(columns*tile_w,rows*tile_h),'#FFFFFF');d=ImageDraw.Draw(sheet)
    for index,(path,label) in enumerate(captures):
        x=(index%columns)*tile_w;y=(index//columns)*tile_h
        with Image.open(path) as img: sheet.paste(img.resize((480,270),Image.Resampling.LANCZOS),(x,y))
        d.text((x+7,y+275),label,font=font(16),fill=INK,anchor='lt')
    sheet.save(spec_path.parent/'contact_sheet.jpg',quality=93)


def main():
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['plates','contact']);p.add_argument('spec',type=Path);a=p.parse_args()
    spec=json.loads(a.spec.read_text())
    if a.mode=='plates':
        for item in spec['plates']:make_plate(item,spec)
    else:contact(a.spec)


if __name__=='__main__':main()
