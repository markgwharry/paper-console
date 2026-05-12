export const formatTimeForDisplay = (time24, timeFormat = '12h') => {
  if (!time24) return '';
  if (timeFormat === '24h') return time24;

  const [hours, minutes] = time24.split(':');
  const h = parseInt(hours, 10);
  const ampm = h >= 12 ? 'PM' : 'AM';
  const h12 = h % 12 || 12;
  return `${h12}:${minutes} ${ampm}`;
};

export const normalizePrintWebhookEndpointPath = (value) => {
  const slug = String(value ?? '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, '-')
    .replace(/^-+|-+$/g, '');

  return slug;
};

export const generatePrintWebhookToken = () => {
  const bytes = new Uint8Array(18);

  if (globalThis.crypto?.getRandomValues) {
    globalThis.crypto.getRandomValues(bytes);
    let binary = '';
    bytes.forEach((byte) => {
      binary += String.fromCharCode(byte);
    });
    return btoa(binary)
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/g, '');
  }

  return `pc1_${Math.random().toString(36).slice(2)}${Math.random().toString(36).slice(2)}`;
};
