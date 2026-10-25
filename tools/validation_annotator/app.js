(function () {
  "use strict";
  const core = window.ValidationAnnotatorCore;
  const element = id => document.getElementById(id);
  const canvas = element("raw-image");
  const context = canvas.getContext("2d");
  const state = { sample: null, bitmap: null, corners: {}, loadRevision: 0 };

  function status(id, message, error = false) {
    element(id).textContent = message;
    element(id).classList.toggle("error", error);
  }

  function clearConfirmation() {
    element("confirm-annotation").checked = false;
    element("annotation-preview").hidden = true;
  }

  function candidateAnnotation() {
    return core.buildAnnotation({
      sample: state.sample, annotatorID: element("annotator-id").value.trim(),
      expectedOutcome: element("expected-outcome").value,
      originalCorners: element("geometry-enabled").checked ? state.corners : null,
      confirmed: element("confirm-annotation").checked
    });
  }

  function updateExport() {
    element("export-label").disabled = true;
    if (!state.sample) return;
    try {
      candidateAnnotation();
      element("export-label").disabled = false;
      status("export-status", "Ready to download your explicitly assigned annotation. This is not an acceptance result.");
    } catch (error) { status("export-status", error.message); }
  }

  function updateCorners() {
    const enabled = element("geometry-enabled").checked;
    element("corner-instructions").hidden = !enabled;
    canvas.classList.toggle("pointing", enabled);
    const count = Object.keys(state.corners).length;
    element("undo-corner").disabled = !enabled || count === 0;
    element("clear-corners").disabled = !enabled || count === 0;
    status("corner-status", count === 4 ? "Four explicit clicks. Check their identities before export." : "Next click: " + core.cornerNames[count]);
    element("corner-values").replaceChildren();
    for (const name of core.cornerNames) {
      const row = document.createElement("li");
      const point = state.corners[name];
      row.textContent = name + (point ? ": x=" + point.x.toFixed(3) + ", y=" + point.y.toFixed(3) : ": not clicked");
      element("corner-values").appendChild(row);
    }
    draw();
    updateExport();
  }

  function draw() {
    if (!state.bitmap || !state.sample) return;
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.drawImage(state.bitmap, 0, 0);
    const displayWidth = canvas.getBoundingClientRect().width || canvas.width;
    const units = canvas.width / displayWidth;
    context.lineWidth = 2 * units;
    context.font = "600 " + (13 * units) + "px system-ui";
    for (const name of core.cornerNames) {
      const point = state.corners[name];
      if (!point) continue;
      context.beginPath();
      context.arc(point.x, point.y, 7 * units, 0, Math.PI * 2);
      context.fillStyle = "#ffffff";
      context.fill();
      context.strokeStyle = "#a33d17";
      context.stroke();
      context.fillStyle = "#a33d17";
      context.fillText(name, point.x + 10 * units, Math.max(16 * units, point.y - 10 * units));
    }
  }

  function zoom() {
    if (!state.sample) return;
    const value = element("image-zoom").value;
    canvas.style.width = value === "fit" ? "100%" : (state.sample.image.width * Number(value)) + "px";
    canvas.style.height = value === "fit" ? "auto" : (state.sample.image.height * Number(value)) + "px";
    draw();
  }

  function showMetadata(sample) {
    element("sample-info").hidden = false;
    const synthetic = sample.source === "synthetic_fixture";
    element("source-status").textContent = synthetic ? "SYNTHETIC FIXTURE — export remains synthetic_fixture" : "Declared physical_camera source — human label requires your explicit action";
    element("source-status").classList.toggle("synthetic", synthetic);
    const details = element("sample-details");
    details.replaceChildren();
    const fields = [["Sample", sample.id], ["Reference", "State " + sample.referenceState + " · " + sample.checkpointID],
      ["Candidate", sample.appVersion + " build " + sample.appBuild], ["Course revision", sample.courseRevision],
      ["Raw PNG", sample.image.width + " × " + sample.image.height + " · SHA-256 matched"],
      ["Paper layout", sample.paperLayoutID === null ? "Not declared in this record" : sample.paperLayoutID + " revision " + sample.paperLayoutRevision]];
    for (const [title, value] of fields) {
      const term = document.createElement("dt"), description = document.createElement("dd");
      term.textContent = title;
      description.textContent = value;
      details.append(term, description);
    }
  }

  async function load() {
    const revision = ++state.loadRevision;
    state.sample = null;
    state.bitmap?.close();
    state.bitmap = null;
    state.corners = {};
    clearConfirmation();
    element("expected-outcome").value = "";
    element("geometry-enabled").checked = false;
    element("annotation-workspace").hidden = true;
    element("sample-info").hidden = true;
    element("export-label").disabled = true;
    const metadataFile = element("metadata-file").files[0];
    const imageFile = element("image-file").files[0];
    if (!metadataFile || !imageFile) {
      status("file-status", "Select both sample.json and its matching image.png. No label assigned.");
      return;
    }
    status("file-status", "Checking raw PNG dimensions and SHA-256…");
    try {
      if (metadataFile.size > 1024 * 1024 || imageFile.size > 64 * 1024 * 1024) throw new Error("Selected files exceed the local size limits.");
      const [metadataText, imageBuffer] = await Promise.all([metadataFile.text(), imageFile.arrayBuffer()]);
      const sample = await core.verifySample(metadataText, new Uint8Array(imageBuffer));
      if (revision !== state.loadRevision) return;
      const bitmap = await createImageBitmap(imageFile);
      if (revision !== state.loadRevision) { bitmap.close(); return; }
      if (bitmap.width !== sample.image.width || bitmap.height !== sample.image.height) {
        bitmap.close();
        throw new Error("Decoded image dimensions differ from the raw metadata. No annotation enabled.");
      }
      state.sample = sample;
      state.bitmap = bitmap;
      canvas.width = sample.image.width;
      canvas.height = sample.image.height;
      element("annotation-workspace").hidden = false;
      element("geometry-enabled").disabled = sample.referenceState !== 2;
      element("geometry-note").textContent = sample.referenceState === 2 ?
        "Optional geometry is available for this flat reopened state. Use actual original-sheet corners only; otherwise leave it off." :
        "Geometry is disabled outside state 2. Export empty landmarks and no width reference; never impute hidden or moved coordinates.";
      showMetadata(sample);
      element("image-zoom").value = "fit";
      zoom();
      updateCorners();
      status("file-status", "File pair verified. Detector predictions remain hidden. No human label has been assigned.");
    } catch (error) {
      if (revision === state.loadRevision) status("file-status", error.message, true);
    }
  }

  element("metadata-file").addEventListener("change", load);
  element("image-file").addEventListener("change", load);
  ["annotator-id", "expected-outcome"].forEach(id => element(id).addEventListener("input", () => { clearConfirmation(); updateExport(); }));
  element("confirm-annotation").addEventListener("change", updateExport);
  element("geometry-enabled").addEventListener("change", () => { state.corners = {}; clearConfirmation(); updateCorners(); });
  element("undo-corner").addEventListener("click", () => {
    delete state.corners[core.cornerNames[Object.keys(state.corners).length - 1]];
    clearConfirmation(); updateCorners();
  });
  element("clear-corners").addEventListener("click", () => { state.corners = {}; clearConfirmation(); updateCorners(); });
  element("image-zoom").addEventListener("change", zoom);
  window.addEventListener("resize", draw);
  canvas.addEventListener("click", event => {
    if (!state.sample || !element("geometry-enabled").checked || Object.keys(state.corners).length >= 4) return;
    const point = core.imagePointFromClient(event.clientX, event.clientY, canvas.getBoundingClientRect(), state.sample.image.width, state.sample.image.height);
    if (!point) return;
    state.corners[core.cornerNames[Object.keys(state.corners).length]] = point;
    clearConfirmation(); updateCorners();
  });
  canvas.addEventListener("mousemove", event => {
    if (!state.sample) return;
    const point = core.imagePointFromClient(event.clientX, event.clientY, canvas.getBoundingClientRect(), state.sample.image.width, state.sample.image.height);
    if (point) element("pointer-position").textContent = "Raw edge pixels: x=" + point.x.toFixed(2) + ", y=" + point.y.toFixed(2);
  });
  element("export-label").addEventListener("click", () => {
    try {
      const annotation = candidateAnnotation();
      const jsonl = core.toJSONL(annotation);
      const url = URL.createObjectURL(new Blob([jsonl], { type: "application/x-ndjson;charset=utf-8" }));
      const link = document.createElement("a");
      link.href = url;
      link.download = "annotation-" + state.sample.id + ".jsonl";
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 2000);
      element("annotation-preview").textContent = jsonl;
      element("annotation-preview").hidden = false;
      status("export-status", "Downloaded one independently assigned annotation. Source: " + annotation.annotationSource + ". No acceptance conclusion.");
    } catch (error) { status("export-status", error.message, true); }
  });
})();
