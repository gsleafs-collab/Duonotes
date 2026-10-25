# DuoNotes

Composition notebooks for the iPhone Duo. Write on lined paper with Apple Pencil, move your writing around with a finger, and unfold the phone to open the notebook into a two page spread.

## What it does

- **Shelf of notebooks.** Each one has a black and white marbled cover with its own pattern and a white title label. Long press a notebook to rename it, change the cover colour or delete it.
- **Opening a notebook** flips the cover open onto lined paper with blue rules and a red margin.
- **One page or two.** Folded (outer screen) you see one page. Unfold the Duo and turn it sideways to get the open book spread with the spine down the middle. Use the book button in the top bar to force one or two pages.
- **Pencil writes, finger moves.** Apple Pencil writes. Drag ink with your finger to pick up that word or doodle and move it. Swipe across blank paper to turn the page.
- **Finger writes mode.** Tap "Finger moves" in the palette to switch, which is handy without a Pencil.
- **Tools:** pen, pencil, highlighter, eraser and lasso, four ink colours and three thicknesses. Undo and redo work across pages.
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
    ToolState.swift        Pens, colours, thickness
  Views/
    LibraryView.swift      Notebook shelf and new notebook sheet
    NotebookView.swift     Open notebook, page turning, tool palette
    PaperPage.swift        Lined paper
    CanvasView.swift       PencilKit canvas and finger move gesture
    CompositionCover.swift Marbled cover
```
