import mermaid from 'mermaid';

let serial = 0;
// Mermaid has shared parser/configuration state. Serialize rendering, including
// theme updates, so documents never race one another within this reader page.
let queue = Promise.resolve();
window.lightmarkRenderDiagram = (source, dark) => {
  const operation = queue.then(async () => {
    if (source.length > 50_000) throw new Error('Diagram exceeds the rendering limit');
    mermaid.initialize({
      startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true,
      maxTextSize: 50_000, maxEdges: 500, theme: dark ? 'dark' : 'default',
      htmlLabels: false, flowchart: { htmlLabels: false },
      secure: ['secure', 'securityLevel', 'startOnLoad', 'maxTextSize', 'maxEdges',
               'suppressErrorRendering', 'htmlLabels', 'flowchart', 'theme', 'themeCSS'],
    });
    const staging = document.createElement('div');
    staging.style.cssText = 'position:absolute;left:-100000px;top:0;visibility:hidden';
    document.body.append(staging);
    try {
      const { svg } = await mermaid.render(`lm-diagram-${++serial}`, source, staging);
      // SVG is displayed as an image, never inserted as active document HTML.
      return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
    } finally { staging.remove(); }
  });
  queue = operation.catch(() => {});
  return operation;
};
