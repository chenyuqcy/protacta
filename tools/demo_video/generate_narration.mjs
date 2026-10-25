// Generate local, un-cloned Kokoro narration. Model weights remain in the
// existing shared cache; no API credentials or external speech service is used.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

const [planArgument, outputArgument] = process.argv.slice(2);
if (!planArgument || !outputArgument) {
  console.error('Usage: node generate_narration.mjs narration_plan.json fresh_output_directory');
  process.exit(2);
}
const dependencyRoot = process.env.PROTACTA_TTS_MODULES || '/Users/adrian/Desktop/QCRI/output/playwright/ixlab-honey-demo-20261005/edit/natural-voice/node_modules';
const sharedCache = process.env.PROTACTA_TTS_CACHE || '/Users/adrian/Desktop/QCRI/output/playwright/ixlab-honey-demo-20261005/edit/natural-voice/model-cache';
const { KokoroTTS } = await import(pathToFileURL(path.join(dependencyRoot, 'kokoro-js/dist/kokoro.js')));
const { StyleTextToSpeech2Model, AutoTokenizer, env } = await import(pathToFileURL(path.join(dependencyRoot, '@huggingface/transformers/dist/transformers.node.mjs')));
const planPath = path.resolve(planArgument);
const rawPlan = await fs.readFile(planPath, 'utf8');
const plan = JSON.parse(rawPlan);
const planHash = crypto.createHash('sha256').update(rawPlan).digest('hex');
const output = path.resolve(outputArgument);
await fs.mkdir(output, { recursive: true });
const manifestPath = path.join(output, 'voice-manifest.json');
const modelName = 'onnx-community/Kokoro-82M-v1.0-ONNX';
const voice = 'af_heart';
const speed = .98;
const leadIn = .16;
const sessionOptions = { intraOpNumThreads: 2, interOpNumThreads: 2, executionMode: 'sequential' };
let manifest;
try {
  manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  if (manifest.planHash !== planHash) throw new Error('Plan changed; choose a fresh voice output directory.');
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
  manifest = { engine: 'Kokoro', packageVersion: '1.2.1', model: modelName, dtype: 'fp32',
    voice, speed, clonedVoice: false, generatedLocally: true, sharedCache, sessionOptions,
    createdAt: new Date().toISOString(), planHash, planPath, leadIn, videos: [], clips: [] };
}
env.cacheDir = sharedCache;
env.allowRemoteModels = false;
console.log('Loading the existing local Kokoro model; CPU threads capped at two.');
const [speechModel, tokenizer] = await Promise.all([
  StyleTextToSpeech2Model.from_pretrained(modelName, { dtype: 'fp32', device: 'cpu',
    cache_dir: sharedCache, local_files_only: true, session_options: sessionOptions }),
  AutoTokenizer.from_pretrained(modelName, { cache_dir: sharedCache, local_files_only: true }),
]);
const tts = new KokoroTTS(speechModel, tokenizer);
for (const video of plan.videos) {
  manifest.videos = manifest.videos.filter(v => v.id !== video.id);
  manifest.videos.push({ id: video.id, source: video.source, duration: video.duration });
  for (const segment of video.segments) {
    if (manifest.clips.some(clip => clip.id === segment.id)) continue;
    const spoken = segment.spoken || segment.text.replaceAll('3D', 'three dee');
    const budget = segment.end - segment.start - leadIn - .08;
    const reusable = manifest.clips.find(clip => clip.spoken === spoken && clip.speed === speed);
    let duration, file, sampleRate;
    if (reusable) {
      ({ duration, file, sampleRate } = reusable);
    } else {
      const generated = await tts.generate(spoken, { voice, speed });
      duration = generated.audio.length / generated.sampling_rate;
      sampleRate = generated.sampling_rate;
      file = `${segment.id}.wav`;
      await generated.save(path.join(output, file));
    }
    if (duration > budget + .005) {
      console.error(`SHORTEN ${segment.id}: ${duration.toFixed(3)} s exceeds ${budget.toFixed(3)} s. No speed-up or truncation applied.`);
      process.exit(3);
    }
    manifest.clips.push({ id: segment.id, videoID: video.id, file, text: segment.text,
      spoken, voice, speed, sampleRate, duration, slotStart: segment.start, slotEnd: segment.end,
      audioStart: segment.start + leadIn, audioEnd: segment.start + leadIn + duration });
    await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
    console.log(`${segment.id}: ${duration.toFixed(3)} s within ${(segment.end - segment.start).toFixed(3)} s window`);
  }
}
manifest.complete = true;
manifest.finishedAt = new Date().toISOString();
manifest.expectedPhrases = plan.videos.reduce((sum, video) => sum + video.segments.length, 0);
if (manifest.clips.length !== manifest.expectedPhrases) throw new Error('Final phrase count differs from plan.');
await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
console.log(`Saved ${manifest.clips.length} narration phrases at a natural .98 speed.`);
// The installed ONNX build can fault in its shutdown cleanup after completed
// inference; all WAV files and the manifest are independently decoded afterward.
process.exit(0);
