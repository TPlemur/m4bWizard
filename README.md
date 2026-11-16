# m4bWizard
A CLI wizard for making m4b audiobooks out of one audio file or a folder of audio files.

how to install:

brew tap tplemur/tools

brew install m4bwizard

Run with:

m4bwizard

I recommend running it in the folder where your target audio files are, but it will accept paths from anywhere (tab completion works when typing paths). It walks you through the steps needed to gather metadata and then runs ffmpeg to make the m4b, saved next to your source audio. You will need ffmpeg (which includes ffprobe) installed.

What it can do:

- **Audio source:** a single file, or every file of one type in a folder (joined in file name order).
- **Metadata:** title, author, narrator, date, genre and summary, pre-filled from the audio when it has them. Anything else found in the file is kept and can be edited by hand.
- **Chapters:** start with none, import a `.cue` file, name them from the file names (folder mode), or reuse the chapters already in the audio. You can edit the list before it is used; the edited list always replaces any chapters already in the source.
- **Cover image:** pick an image file, or strip the cover that is embedded in the audio.

Edits to metadata and chapters (and the "Other Metadata" box) open in `nano`.

Written for the stock bash that ships with macOS (3.2), so no newer bash is needed.

Currently I've only ever tested this on MacOS.
