module.exports = {
  env: {
    browser: true,
    es2021: true,
    node: true,
    jest: true
  },
  extends: [
    'eslint:recommended'
  ],
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module'
  },
  rules: {
    // Code Quality
    'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    'no-console': 'warn',
    'prefer-const': 'error',
    'no-var': 'error',
    
    // Style Consistency
    'indent': ['error', 2],
    'quotes': ['error', 'single'],
    'semi': ['error', 'always'],
    'comma-dangle': ['error', 'never'],
    'object-curly-spacing': ['error', 'always'],
    'array-bracket-spacing': ['error', 'never'],
    
    // Best Practices
    'eqeqeq': ['error', 'always'],
    'no-eval': 'error',
    'no-implied-eval': 'error',
    'no-new-func': 'error',
    'radix': 'error',
    
    // Electron-specific
    'no-process-exit': 'off' // Allow process.exit in main process
  },
  globals: {
    // Electron globals
    '__dirname': 'readonly',
    '__filename': 'readonly',
    'process': 'readonly'
  },
  overrides: [
    {
      files: ['src/renderer/**/*.js'],
      env: {
        browser: true,
        node: false
      },
      globals: {
        'ipcRenderer': 'readonly',
        'shell': 'readonly'
      }
    },
    {
      files: ['src/main.js', 'src/selection-monitor.js', 'src/mac-*.js'],
      env: {
        node: true,
        browser: false
      }
    }
  ]
};