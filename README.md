# DuoNotes

Composition notebooks for the iPhone Duo. Write on lined paper with Apple Pencil, move your writing around with a finger, and unfold the phone to open the notebook into a two page spread.

## What it does

- **Front screen.** The current notebook's marbled cover fills the screen. The books button in the corner switches, adds, renames, recolours or deletes notebooks.
- **Opening a notebook.** Tap the cover or unfold the Duo. The book opens at the last page you had open. Folding the Duo, or Close Book in the pen menu, goes back to the cover.
- **One page or two.** Held upright you get one page. Turn the phone sideways and it opens into a two page spread with a stitched seam down the middle.
- **Page flipping.** Drag from the right edge with a finger to flip forward, or from the left edge to flip back. Flipping past the last page adds fresh paper.
- **Page thumbnails.** Tap the page number at the bottom of a page to see every page and jump to one.
- **Pencil writes, finger moves.** Apple Pencil writes. Drag ink with a finger to pick up that word or doodle and move it.
- **Pen menu.** A small round pen button in the corner opens the menu:
  - Pen, pencil, highlighter, eraser and lasso
  - Three ink colours. Tap the selected one to choose any colour from the colour wheel.
  - Tip size and eraser size, with presets and a slider
  - Finger mode: moves ink or writes
  - Appearance: Auto (follows the phone), Light or Dark
  - Undo, redo and Close Book
- Notebooks save automatically on the device.

## Running it

You need a Mac with Xcode 16 or later.

1. Open `DuoNotes.xcodeproj`.
2. Select the **DuoNotes** target, open **Signing & Capabilities**, and choose your Apple ID under **Team**. Change the bundle identifier from `com.example.DuoNotes` to something unique, such as `com.yourname.DuoNotes`.
3. Plug in your iPhone Duo, pick it as the run destination, and press **Run**.
4. The first time, approve the developer profile on the phone under **Settings > General > VPN & Device Management**.

Apple Pencil on the iPhone Duo needs iOS 27.2 and the USB-C Apple Pencil. Without a Pencil, switch the palette to "Finger writes".

## Project layout

```
DuoNotes/
  DuoNotesApp.swift        App entry point
  Models/
    Notebook.swift         Notebook, Page, cover styles, paper sizes
    NotebookStore.swift    Saving, loading, undo and redo
    PenSettings.swift      Pen, colours, sizes, appearance
  Views/
    HomeView.swift         Full screen cover, bookshelf, new notebook sheet
    NotebookView.swift     Open notebook, seam and pen menu placement
    BookPager.swift        Page curl, lined paper, PencilKit canvas, finger move
    PenMenu.swift          Collapsible pen menu and colour wheel
    PageGridSheet.swift    Page thumbnails
    CompositionCover.swift Marbled cover
```
