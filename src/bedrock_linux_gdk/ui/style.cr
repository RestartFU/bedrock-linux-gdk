module BedrockLinuxGdk
  module UI
    STYLE = <<-CSS
      :root {
        --window-bg-color: #08080a;
        --window-fg-color: #f4f4f5;
        --view-bg-color: #08080a;
        --view-fg-color: #f4f4f5;
        --headerbar-bg-color: #08080a;
        --headerbar-fg-color: #f4f4f5;
        --headerbar-backdrop-color: #08080a;
        --sidebar-bg-color: #050506;
        --sidebar-fg-color: #f4f4f5;
        --popover-bg-color: #151518;
        --dialog-bg-color: #151518;
        --card-bg-color: #101013;
        --accent-bg-color: #22c55e;
        --accent-color: #4ade80;
      }

      window {
        background: #08080a;
        color: #f4f4f5;
        font-family: "DM Sans", "Inter", "Cantarell", sans-serif;
        font-size: 0.95em;
      }

      headerbar {
        min-height: 46px;
        background: #08080a;
        border: none;
        border-bottom: 1px solid #242428;
        box-shadow: none;
      }

      .bol-sidebar {
        background: #050506;
        border-right: 1px solid #242428;
        padding: 12px;
      }

      .bol-brand {
        padding: 10px 8px 18px 8px;
      }

      .bol-nav {
        background: transparent;
        border: none;
        box-shadow: none;
        border-radius: 9px;
        padding: 9px 11px;
      }

      .bol-nav:hover {
        background: alpha(#ffffff, 0.055);
      }

      .bol-nav.selected {
        background: alpha(#ffffff, 0.09);
      }

      .bol-content {
        background: #08080a;
      }

      .bol-card {
        background: #101013;
        border: 1px solid #242428;
        border-radius: 16px;
        padding: 20px;
      }

      .bol-hero {
        background:
          linear-gradient(120deg, alpha(#22c55e, 0.10), transparent 46%),
          #101013;
      }

      .bol-version {
        background: alpha(#ffffff, 0.045);
        border: 1px solid alpha(#ffffff, 0.065);
      }

      .bol-choices {
        background: transparent;
        border: 1px solid alpha(#ffffff, 0.065);
        border-radius: 11px;
      }

      .bol-choices > row {
        background: alpha(#ffffff, 0.045);
        border: none;
        border-radius: 0;
      }

      .bol-choices > row:first-child {
        border-radius: 10px 10px 0 0;
        border-bottom: 1px solid alpha(#ffffff, 0.065);
      }

      .bol-choices > row:last-child {
        border-radius: 0 0 10px 10px;
      }

      button {
        min-height: 34px;
        border-radius: 9px;
        background: alpha(#ffffff, 0.055);
        border: 1px solid alpha(#ffffff, 0.07);
        box-shadow: none;
      }

      button:hover {
        background: alpha(#ffffff, 0.095);
      }

      button.suggested-action {
        background: #22c55e;
        color: #041007;
        border-color: #22c55e;
        font-weight: 700;
      }

      button.suggested-action:hover {
        background: #34d66b;
      }

      button.destructive-action {
        background: alpha(#ef4444, 0.16);
        color: #fca5a5;
        border-color: alpha(#ef4444, 0.28);
      }

      button.flat {
        background: transparent;
        border-color: transparent;
      }

      .bol-account {
        border-radius: 9999px;
        padding-left: 13px;
        padding-right: 13px;
      }

      .bol-log, .bol-log text {
        background: #050506;
        color: #b8b8bf;
        font-family: "JetBrains Mono", "Monospace", monospace;
        font-size: 0.90em;
      }

      .bol-log {
        border: 1px solid #242428;
        border-radius: 12px;
        padding: 10px;
      }

      .bol-status {
        color: alpha(#ffffff, 0.58);
      }

      .bol-success {
        color: #4ade80;
      }

      .bol-warning {
        color: #fbbf24;
      }

      preferencespage {
        background: #08080a;
      }

      preferencesgroup listview > row {
        background: #101013;
        border: 1px solid #242428;
      }

      row.entry, row.combo, row.action {
        background: #101013;
      }

      popover > contents,
      popover.menu > contents {
        background: #151518;
        border: 1px solid alpha(#ffffff, 0.10);
        border-radius: 12px;
      }

      scrollbar, scrollbar trough {
        background: none;
        border: none;
      }

      scrollbar slider {
        min-width: 4px;
        min-height: 4px;
        border-radius: 4px;
        background: alpha(#ffffff, 0.16);
      }
    CSS
  end
end
