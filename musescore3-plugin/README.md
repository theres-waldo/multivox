# Multivox

## Description

This is a [MuseScore](https://musescore.org/en) plugin to help
automate the creation of choral practice tracks.

The plugin operates on a MuseScore score, and exports the
following:

 * An mp3 file containing all voices at equal volume

 * For each part, an mp3 file where the part in question has
   its instrument changed to piano (to make it easier to
   distinguish it from other voices) while the other parts
   have their volumes lowered by a configurable amount.

Due to bugs in MuseScore 4's plugin support, the plugin currently
requires MuseScore 3 to work.

## Setup

  1. Download MuseScore 3 from
     https://musescore.org/en/download#Older-and-unsupported-versions

  2. Copy `multivox.qml` into MuseScore 3's plugin directory,
     e.g. `~/MuseScore3/Plugins`.

  3. Launch MuseScore 3, open `Plugins --> Plugin Manager`, and
     check the "multivox" entry.

## Usage

### For scores created with MuseScore 4:

 * Export the score to musicxml. This can be done in the GUI with
   File --> Export, or on the command line with
   `musesore4 -o piece.musicxml piece.mscz`.

 * Open the exported musicxml file in MuseScore 3. MuseScore may
   complain that the file is invalid but there's an option to open
   it anyways, choose this.

### Once the score is open in MuseScore 3:

 * Run `Plugins --> Export practice files (multivox)`.
 * Select a percentage volume for the de-emphasized parts.
   (50% a good initial choice.)
 * Optionally adjust the export directory.
 * Click `OK` and wait for the export to complete.

## Credits

This plugin is based on https://github.com/multiplenoise/musescore-practice-export
