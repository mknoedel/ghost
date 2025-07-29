class ActionRegistry {
  constructor() {
    this.actions = new Map();
    this.loadBuiltInActions();
  }

  loadBuiltInActions() {
    // Built-in actions
    this.register({
      id: 'copy',
      label: 'Copy',
      icon: '📋',
      handler: async (text, { ipcRenderer }) => {
        await ipcRenderer.invoke('copy-text', text);
        return { success: true, message: 'Copied to clipboard' };
      }
    });

    this.register({
      id: 'search-google',
      label: 'Google',
      icon: '🔍',
      handler: async (text, { shell }) => {
        const searchUrl = `https://www.google.com/search?q=${encodeURIComponent(text)}`;
        shell.openExternal(searchUrl);
        return { success: true, message: 'Opened in browser' };
      }
    });

    this.register({
      id: 'translate',
      label: 'Translate',
      icon: '🌐',
      handler: async (text, { shell }) => {
        const translateUrl = `https://translate.google.com/?text=${encodeURIComponent(text)}`;
        shell.openExternal(translateUrl);
        return { success: true, message: 'Opened translator' };
      }
    });

    this.register({
      id: 'upper-case',
      label: 'UPPER',
      icon: '📝',
      handler: async (text, { ipcRenderer }) => {
        const upperText = text.toUpperCase();
        await ipcRenderer.invoke('copy-text', upperText);
        return { success: true, message: 'Converted to uppercase' };
      }
    });

    this.register({
      id: 'lower-case',
      label: 'lower',
      icon: '📝',
      handler: async (text, { ipcRenderer }) => {
        const lowerText = text.toLowerCase();
        await ipcRenderer.invoke('copy-text', lowerText);
        return { success: true, message: 'Converted to lowercase' };
      }
    });

    this.register({
      id: 'title-case',
      label: 'Title',
      icon: '📝',
      handler: async (text, { ipcRenderer }) => {
        const titleText = text.replace(
          /\w\S*/g,
          txt => txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase()
        );
        await ipcRenderer.invoke('copy-text', titleText);
        return { success: true, message: 'Converted to title case' };
      }
    });

    this.register({
      id: 'word-count',
      label: 'Count',
      icon: '🔢',
      handler: async (text, { ipcRenderer }) => {
        const wordCount = text.trim().split(/\s+/).length;
        const charCount = text.length;
        const message = `${wordCount} words, ${charCount} characters`;
        await ipcRenderer.invoke('copy-text', message);
        return { success: true, message: 'Word count copied' };
      }
    });

    this.register({
      id: 'qr-code',
      label: 'QR Code',
      icon: '📱',
      handler: async (text, { shell }) => {
        const qrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${encodeURIComponent(text)}`;
        shell.openExternal(qrUrl);
        return { success: true, message: 'Generated QR code' };
      }
    });
  }

  register(action) {
    if (!action.id || !action.label || !action.handler) {
      throw new Error('Action must have id, label, and handler');
    }
    this.actions.set(action.id, action);
  }

  unregister(actionId) {
    this.actions.delete(actionId);
  }

  getActions() {
    return Array.from(this.actions.values());
  }

  getAction(actionId) {
    return this.actions.get(actionId);
  }

  async executeAction(actionId, text, context) {
    const action = this.getAction(actionId);
    if (!action) {
      throw new Error(`Action '${actionId}' not found`);
    }

    try {
      return await action.handler(text, context);
    } catch (error) {
      return { success: false, message: error.message };
    }
  }
}

module.exports = ActionRegistry;
