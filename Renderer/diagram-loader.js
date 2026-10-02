let engine;
function loadEngine() {
  if (!engine) engine = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'lightmark-reader://bundle/diagrams.js';
    script.onload = () => resolve(window.lightmarkRenderDiagram);
    script.onerror = () => { script.remove(); engine = null; reject(new Error('Diagram renderer unavailable')); };
    document.head.append(script);
  });
  return engine;
}

let generation = 0;
let observer;
let diagrams = [];
let darkTheme = false;

export function refreshDiagrams(root, dark, newDocument = false) {
  if (!newDocument && dark === darkTheme) return;
  darkTheme = dark;
  const current = ++generation;
  observer?.disconnect();
  if (newDocument) diagrams = [...root.querySelectorAll('pre > code.language-mermaid')].map(code => ({
    source: code.textContent, pre: code.parentElement, image: null
  }));
  observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      observer.unobserve(entry.target);
      const diagram = diagrams.find(item => (item.image ?? item.pre) === entry.target);
      if (!diagram || diagram.source.length > 50_000) continue;
      const visible = diagram.image ?? diagram.pre;
      loadEngine().then(render => {
        if (current !== generation || !visible.isConnected) return null;
        return render(diagram.source, dark);
      }).then(url => {
        if (!url || current !== generation || !visible.isConnected) return;
        const image = new Image();
        image.className = 'lm-diagram';
        image.alt = 'Mermaid diagram';
        image.src = url;
        image.onload = () => {
          if (current !== generation || !visible.isConnected) return;
          visible.replaceWith(image); diagram.image = image;
        };
      }).catch(() => {
        // Invalid/unsupported syntax stays readable and copyable as fenced code.
        if (current === generation && diagram.image?.isConnected) {
          diagram.image.replaceWith(diagram.pre); diagram.image = null;
        }
      });
    }
  }, { rootMargin: '300px' });
  for (const diagram of diagrams) observer.observe(diagram.image ?? diagram.pre);
}
