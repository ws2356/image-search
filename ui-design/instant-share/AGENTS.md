This folder contains design files in the form of a Web Frontend project (./figma-design) and in the form of screenshots (./screenshots) for the instant share feature.

Agents should refer to the ./screenshots folder for a visual of the up-to-date design and refer to figma-design for how the design can be implemented in a web frontend project but need to be adapted for the actual app project which is not necessarily a web frontend project.

Try to implement a high fidelity UI based on the design in this folder. Key points to note:
1. Adopt a clear design system and use the design system to implement the UI. Do not use ad-hoc styles everywhere.
2. The strings in the design are not necessarily the final strings to be used in the app. Agents should refer to the actual strings in the app project for the final strings to be used.

## Architecture of the figma-design project

This document provides a detailed breakdown of how the web frontend project under `./figma-design/` works, so new agents can understand how the Figma design is implemented in React and adapt it for non-web targets (native iOS, Android, or Python/Qt).

---

### 1. Project Identity

- **Name:** `@figma/my-make-file` (v0.0.1, private) — an Autodesk Make-generated export from a Figma design file.
- **Purpose:** A standalone **UI specification viewer** that renders Instant Share (AuShare) cross-device sharing flows (Mobile ↔ PC) as interactive mockups. It is a design review / spec tool, **not** the production app.
- **Entry point:** `src/main.tsx` → renders `<App />` into `#root`.

---

### 2. Tech Stack

| Layer | Technology |
|---|---|
| Framework | React 18.3.1 (no meta-framework) |
| Build | Vite 6.3.5 + `@vitejs/plugin-react` |
| Styling | Tailwind CSS v4 via `@tailwindcss/vite` |
| Animations | `tw-animate-css` (Tailwind-compatible animation utilities) |
| UI Component Library | shadcn/ui (48 components wrapped from `@radix-ui/*` primitives) |
| Icons | `lucide-react` |
| Charts | `recharts` |
| Carousel | `embla-carousel-react` |
| Drawer | `vaul` |
| Drag & Drop | `react-dnd` |
| Routing | `react-router` (included but unused — no routing needed) |
| Theme Toggle | `next-themes` (included but unused) |
| State Management | Pure React `useState` / `useEffect` — **no external state library** |
| Package Manager | pnpm (workspace root at `pnpm-workspace.yaml`) |

---

### 3. Build Configuration

**`vite.config.ts`** — three plugins in order:
1. **`figmaAssetResolver()`** — custom plugin that rewrites `import` paths starting with `figma:asset/` to `src/assets/`. This is a shim for unresolved asset references from the Figma export pipeline.
2. **`@vitejs/plugin-react`** — standard React transform (JSX runtime, Fast Refresh).
3. **`@tailwindcss/vite`** — Tailwind v4's Vite integration (replaces the PostCSS plugin used in v3).

**Aliases:** `@` maps to `./src`.

**PostCSS:** `postcss.config.mjs` exports an empty object — Tailwind v4 handles everything through its Vite plugin.

---

### 4. Directory Structure

```
figma-design/
├── index.html                        # HTML shell (title: "Instant Share Design")
├── package.json                      # Dependencies & scripts
├── pnpm-lock.yaml
├── pnpm-workspace.yaml               # pnpm monorepo root (single package)
├── vite.config.ts                    # Build configuration
├── postcss.config.mjs
├── default_shadcn_theme.css          # Reference: canonical shadcn CSS variables
│                                     # (kept in sync with shadcn globals.css)
├── ATTRIBUTIONS.md                   # Licenses & credits
├── README.md                         # Setup instructions + Figma URL
├── guidelines/
│   └── Guidelines.md                 # Placeholder for AI code-gen guidelines
└── src/
    ├── main.tsx                      # React DOM entry point
    ├── app/
    │   ├── App.tsx                   # ★ CORE: 1015-line single-file UI spec (all screens + frames)
    │   └── components/
    │       ├── figma/
    │       │   └── ImageWithFallback.tsx  # Fallback placeholder when image load fails
    │       └── ui/                        # ★ 48 standard shadcn/ui components
    │           ├── utils.ts               # cn() — clsx + tailwind-merge helper
    │           ├── use-mobile.ts          # useIsMobile() — 768px breakpoint hook
    │           └── {component}.tsx         # One per shadcn component
    └── styles/
        ├── index.css                 # Aggregator: imports fonts, tailwind, theme
        ├── fonts.css                 # @import DM Sans (body) + JetBrains Mono (code)
        ├── tailwind.css              # @import 'tailwindcss' source(none); @source glob
        ├── theme.css                 # ★ CSS custom properties → Tailwind theme tokens
        └── globals.css               # Empty (reserved for project-specific overrides)
```

**Key insight:** All UI application code lives in a single file (`App.tsx`). The 48 shadcn/ui component files in `components/ui/` are a standard library that ships with the project but **none are imported or used** by App.tsx — they're available for future expansion. App.tsx builds its own UI using inline Tailwind classes.

---

### 5. Design System & Theming

#### 5.1 CSS Architecture (`src/styles/`)

```
index.css
  ├── fonts.css       — Google Fonts: DM Sans (300–700, italic), JetBrains Mono
  ├── tailwind.css    — @import 'tailwindcss'; @source '../**/*.{js,ts,jsx,tsx}'; + tw-animate-css
  └── theme.css       — CSS custom properties → @theme inline → @layer base
```

#### 5.2 Theme Tokens (`theme.css`)

Uses three distinct CSS mechanisms:

1. **`@custom-variant dark (&:is(.dark *))`** — defines how dark mode is activated
2. **`:root` and `.dark` blocks** — CSS custom properties (like `--background`, `--foreground`, `--primary`). The default (`:root`) uses a dark theme with deep navy (`#090b12`) background and blue (`#3b7dfa`) primary. The `.dark` class uses standard oklch values.
3. **`@theme inline { ... }`** — maps CSS variables to Tailwind v4 design tokens (e.g., `--color-primary: var(--primary)`), so they work with Tailwind utility classes like `bg-primary`, `text-foreground`, `border-border`.
4. **`@layer base`** — default typography: `html { font-size: 15px }`, headings (h1–h4) use `--text-{size}` with `font-weight-medium`, buttons and inputs inherit base styles.

**Color palette** (light=dark by default since `:root` IS dark):

| Token | Value | Usage |
|---|---|---|
| `--background` | `#090b12` | Deep navy page background |
| `--foreground` | `#e8eaf0` | Light text on dark bg |
| `--primary` | `#3b7dfa` | Blue accent (buttons, selections) |
| `--muted-foreground` | `#6b7090` | De-emphasized text |
| `--border` | `rgba(255,255,255,0.07)` | Subtle white borders on dark |
| `--radius` | `0.625rem` | 10px base border radius |

#### 5.3 Typography

- **Body font:** DM Sans (sans-serif) with JetBrains Mono for code/monospace elements.
- **Base size:** 15px (`--font-size`).
- **Headings:** Stack at `text-2xl` (h1), `text-xl` (h2), `text-lg` (h3), `text-base` (h4).

---

### 6. Core Architecture: The UI State Machine

The entire application is driven by a **declarative state machine** defined as a configuration object and rendered via React state.

#### 6.1 Flow Configuration (`FLOWS`)

```typescript
type FlowKey = "m2p" | "p2m" | "global";

const FLOWS = {
  m2p: {
    label: "Mobile → PC",
    states: [
      { id: "m2p-empty",     label: "Device Selector — Empty",    mobile: "sel-empty",    pc: "pc-idle"      },
      { id: "m2p-scan",      label: "Device Selector — Scanning", mobile: "sel-scanning", pc: "pc-idle"      },
      { id: "m2p-found",     label: "Device Selector — Found",    mobile: "sel-found",    pc: "pc-idle"      },
      { id: "m2p-pin",       label: "PIN Verification",           mobile: "m-pin",        pc: "pc-pin"       },
      { id: "m2p-done-file", label: "Complete — Image / File",    mobile: "m-sent",       pc: "pc-recv-file" },
      { id: "m2p-done-text", label: "Complete — Text",            mobile: "m-sent",       pc: "pc-recv-text" },
    ],
  },
  p2m: {
    label: "PC → Mobile",
    states: [
      { id: "p2m-qr",    label: "QR Code Window",         mobile: "m-waiting",    pc: "pc-qr"     },
      { id: "p2m-text",  label: "Received — Text",        mobile: "m-recv-text",  pc: "pc-closed" },
      { id: "p2m-image", label: "Received — Images",      mobile: "m-recv-image", pc: "pc-closed" },
      { id: "p2m-files", label: "Received — Files",       mobile: "m-recv-files", pc: "pc-closed" },
    ],
  },
  global: {
    label: "Global",
    states: [
      { id: "global-loading", label: "Loading State", mobile: "m-loading", pc: "pc-qr"    },
      { id: "global-error",   label: "Error State",   mobile: "m-error",   pc: "pc-error" },
    ],
  },
};
```

Each state entry maps to **two screen identifiers** — one for the mobile frame and one for the PC frame — enabling parallel cross-device state transitions.

#### 6.2 React State

```typescript
const [flow, setFlow] = useState<FlowKey>("m2p");
const [stateId, setStateId] = useState("m2p-empty");
```

The `App` component renders:
1. A header with a **flow tab switcher** and a **state dropdown selector**
2. A canvas with `MobilePhoneFrame` and `PCDialogFrame` side by side
3. Each frame receives the `mobile` / `pc` screen key and delegates to `renderMobile()` / `renderPC()` switch-case functions

#### 6.3 Screen Rendering Functions

- **`renderMobile(screen)`** — maps 11 screen keys to components (MSelEmpty, MSelScanning, MSelFound, MPinEntry, MSent, MWaiting, MRecvText, MRecvImage, MRecvFiles, MLoading, MError)
- **`renderPC(screen)`** — maps 7 screen keys to components (PCQRCode, PCPinDisplay, PCIdle, PCRecvFile, PCRecvText, PCClosedSuccess, PCError)

---

### 7. Component Architecture

#### 7.1 Shared Utility Components (defined in App.tsx)

| Component | Lines | Purpose |
|---|---|---|
| `QRCodeSVG` | 71–82 | Programmatic QR code using deterministic pseudo-random 25×25 grid |
| `PhotoThumb` | 98–127 | Gradient photo thumbnail with selection ring and checkmark overlay |
| `SharePayloadBadge` | 131–145 | File info card (name + size + image icon) used as a shared payload summary |
| `Spinner` | 147–154 | CSS rotation animation spinner (border trick) |

#### 7.2 Mobile Screen Components (App.tsx, lines 158–569)

| Screen Component | Lines | Key UI Details |
|---|---|---|
| `MSelEmpty` | 158–182 | Bottom sheet with "No Devices Found" dashed zone, disabled Send button |
| `MSelScanning` | 184–207 | Bottom sheet with pulse-animated "Scanning…" badge, spinner in search row |
| `MSelFound` | 209–242 | Device card (MacBook Pro) with blue check circle, enabled "Send to MacBook Pro" CTA |
| `MPinEntry` | 244–309 | 4-digit PIN boxes with phone-style numeric keypad (sub-labels on keys 2–9), cancel flow |
| `MSent` | 312–334 | "Sent!" success with green checkmark + concentric ring animation, file summary |
| `MWaiting` | 336–351 | Camera icon + spinner, "Point Camera at QR" instructional text |
| `MRecvText` | 354–396 | Header bar, scrollable `<pre>` block, copy-to-clipboard with 2s temp "Copied!" state |
| `MRecvImage` | 398–454 | 1-large + 2-small hero row + 6-grid bottom, multi-select with toggle (all/clear), Save/Share buttons |
| `MRecvFiles` | 456–538 | File list (PNG/PDF/ZIP) with per-file status (done/syncing/queued), progress bar |
| `MLoading` | 540–551 | Centered spinner + "Connecting…" text |
| `MError` | 553–569 | Red alert icon + error message + "Try Again" button |

#### 7.3 PC Screen Components (App.tsx, lines 573–764)

| Screen Component | Lines | Key UI Details |
|---|---|---|
| `PCQRCode` | 573–606 | QR code in white card with blue corner accents, device name + IP display, Cancel button |
| `PCPinDisplay` | 608–643 | Large PIN display (3847), amber lock icon, pulse "Waiting for PIN" indicator, animated progress bar |
| `PCIdle` | 646–656 | WiFi icon + "Ready to Receive" minimal state |
| `PCRecvFile` | 658–693 | Success state with file card (shows Downloads path), "Close" + "Show in Finder" actions |
| `PCRecvText` | 696–733 | Success state with truncated text preview, "Close" + "Copy Text" with temp state |
| `PCClosedSuccess` | 736–745 | "Transfer Complete" green check, auto-close hint |
| `PCError` | 748–763 | "Connection Lost" with retry button |

#### 7.4 Device Frame Components (App.tsx, lines 766–907)

**`MobilePhoneFrame`** (lines 800–871):
- Renders a realistic **iPhone mockup** with:
  - Dynamic Island (black pill at top center)
  - Side buttons (volume up/down, action button, power)
  - Status bar with live clock (updated every 30s via `setInterval`), signal bars, Wi-Fi icon, battery indicator (80% fill)
  - Screen area that wraps `renderMobile(screen)`
  - Home indicator pill
- Dimensions: 335×680 screen area, rounded corners with multi-layer shadows

**`PCDialogFrame`** (lines 874–907):
- Renders a **macOS-style dialog window** with:
  - Mac traffic light buttons (red/yellow/green with inset shadow)
  - "Instant Share" centered title bar
  - Inner content area wrapping `renderPC(screen)`
- Dimensions: 400×480px

Both frames are enclosed in a labeled container ("Mobile" / "Desktop") and rendered side by side on the canvas.

#### 7.5 Header / Controls (App.tsx, lines 933–997)

- **Brand area:** Blue square logo with cross-arrow icon
- **Flow tabs:** "Mobile → PC", "PC → Mobile", "Global" — pill-style toggle with blue active state
- **State dropdown:** `<select>` populating the current flow's states

The page background is a radial gradient (`#1a2040 → #090b12`) with a subtle dot-grid overlay.

---

### 8. Key Implementation Patterns

#### 8.1 QR Code Generation (deterministic, no library)

```typescript
function makeQRGrid(n = 25): boolean[][] // lines 44–67
```

- Creates a 25×25 boolean grid
- Places 3 finder patterns (7×7 in corners) with internal alignment patterns
- Fills remaining cells with pseudo-random data using a **seeded LCG** (`s = 0xdeadbeef; s = (s * 1664525 + 1013904223) >>> 0`)
- The seed constant and threshold (0.46) produce a deterministic QR-like appearance without needing `qrcode` library

**Rendering:** `QRCodeSVG` maps the grid to SVG `<rect>` elements at `size/25` per cell.

#### 8.2 PIN Entry (simulated phone keypad)

`MPinEntry` simulates a phone-style numeric input:
- 4 digit boxes with visual states: empty (dim placeholder), active (blue glow ring), filled (bold digit)
- Keypad grid with 1–9, empty slot, 0, and "del" (backspace)
- Sub-labels (ABC/DEF/etc.) on digit keys 2–9
- Cancel button to clear all digits

#### 8.3 Photo Grid Layout

`MRecvImage` uses a hybrid layout:
- **Hero row:** `<div flex gap-[1px]>` with 1 large thumbnail (`flex: 1`) + 2 small stacked (`w-1/3 flex-col`)
- **Grid section:** `<div className="grid grid-cols-3 gap-[1px]">` with 6 equal thumbnails
- All 9 thumbnails are selectable; selection state stored as `Set<number>` in `useState`
- A "Select All / Deselect All" toggle and bottom action bar (Save {count} / Share)

#### 8.4 File Transfer Progression

`MRecvFiles` models a queue of 3 files with distinct states:
- **done** (PNG): green checkmark, emerald accent
- **syncing** (PDF): blue spinner, blue border glow
- **queued** (ZIP): clock icon, 50% opacity
- A live progress section at the bottom shows "Receiving file 2 of 3…" with progress percentage

#### 8.5 Copy-to-Clipboard with Temporal Feedback

Both `MRecvText` and `PCRecvText` use a common pattern:
```typescript
const [copied, setCopied] = useState(false);
// On click:
setCopied(true);
setTimeout(() => setCopied(false), 2000);
```
This flips the button to a green "Copied!" state for 2 seconds, then reverts.

#### 8.6 Device Time Simulation

`MobilePhoneFrame` runs a `setInterval` every 30 seconds to update the status bar clock:
```typescript
const [time, setTime] = useState(formatTime(new Date()));
useEffect(() => {
  const t = setInterval(() => setTime(formatTime(new Date())), 30000);
  return () => clearInterval(t);
}, []);
```

#### 8.7 Image Error Fallback

`ImageWithFallback` (`src/app/components/figma/ImageWithFallback.tsx`) wraps `<img>` with:
- A `useState(false)` `didError` flag
- On `onError`, renders an SVG placeholder (landscape + mountain icon) in a gray container
- Preserves the original `src` URL as `data-original-url` for debugging

---

### 9. Data Flow Summary

```
User Action
  │
  ├─ Click flow tab → handleFlowChange(f) → setFlow(f) + setStateId(first state)
  │
  ├─ Select from dropdown → setStateId(newId)
  │
  └─ (Inside a screen) Local useState changes
       └─ MPinEntry: addDigit/del → local PIN state
       └─ MRecvImage: toggle(i) → Set<number> selection
       └─ MRecvText/PCRecvText: copy click → 2s "Copied!" feedback
       └─ MobilePhoneFrame: setInterval → time update
```

**No cross-component state communication.** Each screen component is fully self-contained with `useState`. The only "shared" state is the `flow` + `stateId` pair in the top-level `App` component, which determines which pair of screens gets mounted.

---

### 10. Notable Observations for Agents

1. **Single-file design vs. production architecture:** App.tsx at 1015 lines is typical for a Figma export / spec tool. In a production backend (Python/Qt, SwiftUI, or React Native), you would **never** keep all screens in one file. Break out each screen to its own component file.

2. **No actual business logic:** The PIN is static (`3847` on PC side; no validation on mobile), the QR code is decorative, the device discovery is mocked, and file transfer is simulated with hardcoded data. This is a **visual specification**, not a working app.

3. **shadcn/ui library is present but unused** in the app screens. All styling in App.tsx is hand-rolled Tailwind classes. The library is included as a resource for future development.

4. **No routing** — everything is a single-page with state-driven conditional rendering. `react-router` is in `package.json` but not used.

5. **`src/styles/globals.css` is empty** — all global styles are in `theme.css` (Tailwind v4).

6. **Design system vs. inline styles:** The App.tsx code uses `className` for most styling but resorts to inline `style` props for:
   - Dynamic/calculated values (gradient stops, dimensions, progress bar width)
   - Complex CSS properties Tailwind can't express concisely (radial gradients, multi-layered box-shadows)
   - Animation properties tied to state

7. **When adapting to another platform:**
   - **Design tokens** (CSS custom properties in theme.css) map naturally to platform equivalents: SwiftUI `@Environment` values, Android `Resource.Theme` attributes, or Python/Qt style sheets.
   - **Component granularity** should explode one file → N files (one per screen + shared components).
   - **The device frames** (`MobilePhoneFrame`, `PCDialogFrame`) represent the OS chrome; the inner screens represent the app content. In a real app, only the content screens are needed.

---

### 11. Quick Reference: Component-to-Screen Mapping

| State ID | Mobile Component | PC Component |
|---|---|---|
| `m2p-empty` | `MSelEmpty` — bottom sheet, no devices | `PCIdle` — waiting |
| `m2p-scan` | `MSelScanning` — scanning spinner | `PCIdle` — waiting |
| `m2p-found` | `MSelFound` — device found, send ready | `PCIdle` — waiting |
| `m2p-pin` | `MPinEntry` — 4-digit PIN keypad | `PCPinDisplay` — show PIN 3847 |
| `m2p-done-file` | `MSent` — sent success | `PCRecvFile` — file received |
| `m2p-done-text` | `MSent` — sent success | `PCRecvText` — text received |
| `p2m-qr` | `MWaiting` — camera/qr | `PCQRCode` — QR code display |
| `p2m-text` | `MRecvText` — view text | `PCClosedSuccess` — done |
| `p2m-image` | `MRecvImage` — photo grid | `PCClosedSuccess` — done |
| `p2m-files` | `MRecvFiles` — file list | `PCClosedSuccess` — done |
| `global-loading` | `MLoading` — spinner | `PCQRCode` — QR display |
| `global-error` | `MError` — connection failed | `PCError` — connection lost |