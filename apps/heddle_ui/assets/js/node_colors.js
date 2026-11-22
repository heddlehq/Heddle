// The color of the nodes of a category, as the canvas and the sidebar's drag draw them.
const COLORS = {
  'trigger': 'var(--node-trigger)',
  'flow_control': 'var(--node-flow-control)',
  'code': 'var(--node-code)',
  'data_manipulation': 'var(--node-data)',
  'http': 'var(--node-integration)',
  'database': 'var(--node-integration)',
  'email': 'var(--node-integration)',
  'ftp': 'var(--node-integration)',
  'google_sheets': 'var(--node-integration)',
  's3': 'var(--node-integration)',
  'slack': 'var(--node-integration)',
  'utility': 'var(--node-utility)',
  'default': 'var(--node-utility)'
};
export const categoryColor = (category) => COLORS[category] || COLORS['default'];
