const state = {
  scale: null,
  unit: "ft",
  mode: "idle",
  planLoaded: false,
  rooms: [],
  calibrationPoints: [],
  roomDraftStart: null,
  roomId: 1,
};

const elements = {
  fileInput: document.getElementById("pdf-upload"),
  fileName: document.getElementById("file-name"),
  clearPlan: document.getElementById("clear-plan"),
  unitSelect: document.getElementById("unit-select"),
  knownLength: document.getElementById("known-length"),
  calibrateMode: document.getElementById("calibrate-mode"),
  roomMode: document.getElementById("room-mode"),
  roomName: document.getElementById("room-name"),
  modeLabel: document.getElementById("mode-label"),
  scaleLabel: document.getElementById("scale-label"),
  statusText: document.getElementById("status-text"),
  canvas: document.getElementById("pdf-canvas"),
  overlay: document.getElementById("overlay"),
  emptyState: document.getElementById("empty-state"),
  roomCount: document.getElementById("room-count"),
  totalArea: document.getElementById("total-area"),
  roomTableBody: document.getElementById("room-table-body"),
  undoRoom: document.getElementById("undo-room"),
};

const ctx = elements.canvas.getContext("2d");

if (window.pdfjsLib) {
  window.pdfjsLib.GlobalWorkerOptions.workerSrc =
    "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/4.3.136/pdf.worker.min.js";
}

const unitFactors = {
  in: 1,
  ft: 12,
  m: 39.3701,
};

function setMode(mode) {
  state.mode = mode;
  elements.modeLabel.textContent = mode === "idle" ? "Idle" : mode === "calibrate" ? "Calibrating" : "Drawing room";
  elements.overlay.classList.toggle("active", mode !== "idle");

  if (mode === "calibrate") {
    state.roomDraftStart = null;
    state.calibrationPoints = [];
    setStatus("Click two points on the floor plan that match a known real-world distance.");
  } else if (mode === "room") {
    if (!state.scale) {
      setStatus("Calibrate the floor plan before drawing rooms.");
      state.mode = "idle";
      elements.modeLabel.textContent = "Idle";
      elements.overlay.classList.remove("active");
      return;
    }
    setStatus("Click and drag to trace a room rectangle.");
  } else {
    setStatus(state.planLoaded ? "Plan ready." : "Upload a PDF to begin.");
  }

  redrawOverlay();
}

function setStatus(message) {
  elements.statusText.textContent = message;
}

function formatNumber(value) {
  return Number.isInteger(value) ? `${value}` : value.toFixed(2).replace(/\.00$/, "");
}

function squareUnitLabel() {
  return `${state.unit}^2`;
}

function roomColor(index) {
  const palette = ["#d66a2d", "#1e847f", "#b4485d", "#6d58a8", "#3c7c35", "#cc8f1a"];
  return palette[index % palette.length];
}

function getRoomMeasurements(room) {
  const width = room.widthPx * state.scale;
  const height = room.heightPx * state.scale;
  return {
    width,
    height,
    area: width * height,
  };
}

function getPointFromEvent(event) {
  const rect = elements.overlay.getBoundingClientRect();
  return {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top,
  };
}

async function loadPdf(file) {
  if (!window.pdfjsLib) {
    setStatus("PDF rendering library failed to load. Check your internet connection and refresh.");
    return;
  }

  const bytes = await file.arrayBuffer();
  const pdf = await window.pdfjsLib.getDocument({ data: bytes }).promise;
  const page = await pdf.getPage(1);
  const viewport = page.getViewport({ scale: 1.5 });

  elements.canvas.width = viewport.width;
  elements.canvas.height = viewport.height;
  elements.overlay.setAttribute("width", viewport.width);
  elements.overlay.setAttribute("height", viewport.height);
  elements.overlay.setAttribute("viewBox", `0 0 ${viewport.width} ${viewport.height}`);
  elements.overlay.style.width = `${viewport.width}px`;
  elements.overlay.style.height = `${viewport.height}px`;

  await page.render({ canvasContext: ctx, viewport }).promise;

  state.planLoaded = true;
  state.rooms = [];
  state.scale = null;
  state.calibrationPoints = [];
  state.roomDraftStart = null;
  state.roomId = 1;

  elements.emptyState.hidden = true;
  elements.fileName.textContent = file.name;
  elements.scaleLabel.textContent = "Not calibrated";
  setMode("idle");
  updateSummary();
}

function clearPlan() {
  ctx.clearRect(0, 0, elements.canvas.width, elements.canvas.height);
  elements.canvas.width = 0;
  elements.canvas.height = 0;
  state.planLoaded = false;
  state.rooms = [];
  state.scale = null;
  state.calibrationPoints = [];
  state.roomDraftStart = null;
  elements.overlay.innerHTML = "";
  elements.overlay.removeAttribute("viewBox");
  elements.overlay.style.width = "0";
  elements.overlay.style.height = "0";
  elements.fileName.textContent = "No PDF loaded";
  elements.emptyState.hidden = false;
  elements.knownLength.value = "";
  elements.fileInput.value = "";
  updateSummary();
  setMode("idle");
}

function distance(a, b) {
  return Math.hypot(b.x - a.x, b.y - a.y);
}

function applyCalibration() {
  const knownLength = Number(elements.knownLength.value);
  if (state.calibrationPoints.length !== 2) {
    setStatus("Choose two calibration points on the plan first.");
    return;
  }

  if (!knownLength || knownLength <= 0) {
    setStatus("Enter a valid known line length.");
    return;
  }

  const pixels = distance(state.calibrationPoints[0], state.calibrationPoints[1]);
  if (pixels <= 0) {
    setStatus("Calibration points must be different.");
    return;
  }

  state.scale = knownLength / pixels;
  elements.scaleLabel.textContent = `1 px = ${formatNumber(state.scale)} ${state.unit}`;
  setStatus("Scale calibrated. Switch to Draw room to trace spaces.");
  setMode("idle");
}

function addRoom(start, end) {
  const x = Math.min(start.x, end.x);
  const y = Math.min(start.y, end.y);
  const widthPx = Math.abs(end.x - start.x);
  const heightPx = Math.abs(end.y - start.y);

  if (widthPx < 8 || heightPx < 8) {
    setStatus("Room boxes need a little size to be saved.");
    return;
  }

  const room = {
    id: state.roomId++,
    name: elements.roomName.value.trim() || `Room ${state.rooms.length + 1}`,
    x,
    y,
    widthPx,
    heightPx,
    color: roomColor(state.rooms.length),
  };

  state.rooms.push(room);
  elements.roomName.value = "";
  updateSummary();
  redrawOverlay();
  setStatus(`Added ${room.name}.`);
}

function drawDraftRoom(currentPoint) {
  redrawOverlay();
  if (!state.roomDraftStart || !currentPoint) {
    return;
  }

  const draft = document.createElementNS("http://www.w3.org/2000/svg", "rect");
  draft.setAttribute("x", Math.min(state.roomDraftStart.x, currentPoint.x));
  draft.setAttribute("y", Math.min(state.roomDraftStart.y, currentPoint.y));
  draft.setAttribute("width", Math.abs(currentPoint.x - state.roomDraftStart.x));
  draft.setAttribute("height", Math.abs(currentPoint.y - state.roomDraftStart.y));
  draft.setAttribute("class", "room-shape");
  draft.setAttribute("fill", "#d66a2d");
  draft.setAttribute("stroke", "#9e4312");
  elements.overlay.appendChild(draft);
}

function redrawOverlay() {
  elements.overlay.innerHTML = "";

  state.rooms.forEach((room) => {
    const rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    rect.setAttribute("x", room.x);
    rect.setAttribute("y", room.y);
    rect.setAttribute("width", room.widthPx);
    rect.setAttribute("height", room.heightPx);
    rect.setAttribute("class", "room-shape");
    rect.setAttribute("fill", room.color);
    rect.setAttribute("stroke", room.color);
    elements.overlay.appendChild(rect);

    const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
    label.setAttribute("x", room.x + 10);
    label.setAttribute("y", room.y + 22);
    label.setAttribute("fill", room.color);
    label.setAttribute("class", "room-label");
    label.textContent = room.name;
    elements.overlay.appendChild(label);
  });

  if (state.calibrationPoints.length > 0) {
    state.calibrationPoints.forEach((point) => {
      const dot = document.createElementNS("http://www.w3.org/2000/svg", "circle");
      dot.setAttribute("cx", point.x);
      dot.setAttribute("cy", point.y);
      dot.setAttribute("r", 5);
      dot.setAttribute("class", "measure-dot");
      elements.overlay.appendChild(dot);
    });
  }

  if (state.calibrationPoints.length === 2) {
    const [first, second] = state.calibrationPoints;
    const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
    line.setAttribute("x1", first.x);
    line.setAttribute("y1", first.y);
    line.setAttribute("x2", second.x);
    line.setAttribute("y2", second.y);
    line.setAttribute("class", "measure-line");
    elements.overlay.appendChild(line);
  }
}

function updateSummary() {
  elements.roomCount.textContent = `${state.rooms.length}`;
  const totalArea = state.rooms.reduce((sum, room) => sum + getRoomMeasurements(room).area, 0);
  elements.totalArea.textContent = `${formatNumber(totalArea)} ${squareUnitLabel()}`;

  if (state.rooms.length === 0) {
    elements.roomTableBody.innerHTML = '<tr class="empty-row"><td colspan="4">No rooms mapped yet.</td></tr>';
    return;
  }

  elements.roomTableBody.innerHTML = state.rooms
    .map((room) => {
      const measurements = getRoomMeasurements(room);
      return `
        <tr>
          <td>${room.name}</td>
          <td>${formatNumber(measurements.width)} ${state.unit}</td>
          <td>${formatNumber(measurements.height)} ${state.unit}</td>
          <td>${formatNumber(measurements.area)} ${squareUnitLabel()}</td>
        </tr>
      `;
    })
    .join("");
}

elements.fileInput.addEventListener("change", async (event) => {
  const [file] = event.target.files || [];
  if (!file) {
    return;
  }

  if (file.type !== "application/pdf" && !file.name.toLowerCase().endsWith(".pdf")) {
    setStatus("Please choose a PDF floor plan.");
    return;
  }

  setStatus("Rendering the first page of your PDF...");
  try {
    await loadPdf(file);
  } catch (error) {
    console.error(error);
    setStatus("The PDF could not be rendered. Try a different file.");
  }
});

elements.clearPlan.addEventListener("click", clearPlan);

elements.unitSelect.addEventListener("change", (event) => {
  const previousUnit = state.unit;
  state.unit = event.target.value;
  if (state.scale) {
    state.scale = state.scale * (unitFactors[state.unit] / unitFactors[previousUnit]);
    elements.scaleLabel.textContent = `1 px = ${formatNumber(state.scale)} ${state.unit}`;
  }
  updateSummary();
});

elements.calibrateMode.addEventListener("click", () => {
  if (!state.planLoaded) {
    setStatus("Upload a PDF first.");
    return;
  }
  setMode("calibrate");
});

elements.roomMode.addEventListener("click", () => {
  if (!state.planLoaded) {
    setStatus("Upload a PDF first.");
    return;
  }
  setMode("room");
});

elements.knownLength.addEventListener("change", () => {
  if (state.mode === "calibrate" && state.calibrationPoints.length === 2) {
    applyCalibration();
  }
});

elements.overlay.addEventListener("click", (event) => {
  if (state.mode !== "calibrate") {
    return;
  }

  const point = getPointFromEvent(event);
  if (state.calibrationPoints.length === 2) {
    state.calibrationPoints = [point];
  } else {
    state.calibrationPoints.push(point);
  }

  redrawOverlay();

  if (state.calibrationPoints.length === 2) {
    applyCalibration();
  }
});

elements.overlay.addEventListener("pointerdown", (event) => {
  if (state.mode !== "room" || !state.scale) {
    return;
  }

  state.roomDraftStart = getPointFromEvent(event);
  elements.overlay.setPointerCapture(event.pointerId);
});

elements.overlay.addEventListener("pointermove", (event) => {
  if (state.mode !== "room" || !state.roomDraftStart) {
    return;
  }

  drawDraftRoom(getPointFromEvent(event));
});

elements.overlay.addEventListener("pointerup", (event) => {
  if (state.mode !== "room" || !state.roomDraftStart) {
    return;
  }

  const end = getPointFromEvent(event);
  addRoom(state.roomDraftStart, end);
  state.roomDraftStart = null;
});

elements.undoRoom.addEventListener("click", () => {
  if (state.rooms.length === 0) {
    setStatus("There are no rooms to remove yet.");
    return;
  }

  state.rooms.pop();
  redrawOverlay();
  updateSummary();
  setStatus("Removed the last room.");
});

updateSummary();
