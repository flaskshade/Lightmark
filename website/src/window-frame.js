// Pixel-sized continuous corners retain their shape at every window size.
export function installWindowFrame(window) {
  const shell = document.createElement('div');
  shell.className = 'window-shell';
  window.replaceWith(shell);
  shell.append(window);
  const ns = 'http://www.w3.org/2000/svg';
  const rim = document.createElementNS(ns, 'svg');
  rim.classList.add('window-rim');
  rim.setAttribute('aria-hidden', 'true');
  const edge = document.createElementNS(ns, 'path');
  const highlight = document.createElementNS(ns, 'path');
  edge.setAttribute('class', 'window-edge');
  highlight.setAttribute('class', 'window-highlight');
  rim.append(edge, highlight);
  shell.append(rim);
  const shadow = document.createElementNS(ns, 'svg');
  shadow.classList.add('window-shadow');
  shadow.setAttribute('aria-hidden','true');
  shadow.innerHTML = `<defs><filter id="native-window-shadow" x="-50%" y="-50%" width="200%" height="200%" color-interpolation-filters="sRGB"><feDropShadow dx="0" dy="1" stdDeviation="1" flood-opacity=".18"/><feDropShadow dx="0" dy="10" stdDeviation="12" flood-opacity=".2"/><feDropShadow dx="0" dy="26" stdDeviation="24" flood-opacity=".16"/><feComposite operator="out" in2="SourceAlpha"/></filter></defs>`;
  const shadowShape = document.createElementNS(ns,'path');
  shadowShape.setAttribute('fill','black');
  shadowShape.setAttribute('filter','url(#native-window-shadow)');
  shadow.append(shadowShape);
  shell.prepend(shadow);
  function contour(w, h, inset) {
    // Exported from SwiftUI RoundedRectangle(cornerRadius: 16, style: .continuous)
    // on macOS 27, using tools/export-native-corners.swift. Three native cubic
    // segments per corner; keep the rim concentric with the outer contour.
    const radius = 16 - inset;
    const scale = radius / 16;
    const extent = 24.45863914489746 * scale;
    const segments = [
      [0,17.41584014892578, 0,13.894512176513672, 1.198582410812378,10.103903770446777],
      [2.7049601078033447,5.965184211730957, 5.965184211730957,2.7049601078033447, 10.103903770446777,1.198582410812378],
      [13.894512176513672,0, 17.41584014892578,0, 24.45863914489746,0]
    ];
    const width = w - 2 * inset, height = h - 2 * inset;
    const transforms = [
      (x,y) => [x,y],
      (x,y) => [width-y,x],
      (x,y) => [width-x,height-y],
      (x,y) => [y,height-x]
    ];
    const point = (transform,x,y) => transform(x,y).map(v => v + inset).join(' ');
    let path = '';
    transforms.forEach((transform,index) => {
      path += `${index ? 'L' : 'M'} ${point(transform,0,extent)} `;
      for (const segment of segments) {
        path += 'C ';
        for (let i = 0; i < 6; i += 2) path += point(transform,segment[i]*scale,segment[i+1]*scale) + ' ';
      }
    });
    return path + 'Z';
  }
  const observer = new ResizeObserver(([entry]) => {
    const { width, height } = entry.contentRect;
    if (!width || !height) return;
    const outline = contour(width, height, 0);
    // Safari's backdrop layer can escape clip-path at the corners. An alpha
    // mask clips the composited material itself, including its blurred backdrop.
    const mask = `url("data:image/svg+xml,${encodeURIComponent(`<svg xmlns='http://www.w3.org/2000/svg' width='${width}' height='${height}' viewBox='0 0 ${width} ${height}'><path fill='white' d='${outline}'/></svg>`)}")`;
    window.style.clipPath = 'none';
    window.style.maskImage = mask;
    window.style.webkitMaskImage = mask;
    shadow.setAttribute('viewBox', `0 0 ${width} ${height}`);
    shadowShape.setAttribute('d',outline);
    rim.setAttribute('viewBox', `0 0 ${width} ${height}`);
    edge.setAttribute('d', contour(width, height, .5));
    highlight.setAttribute('d', contour(width, height, 1.5));
  });
  observer.observe(window);
}
