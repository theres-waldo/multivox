import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Dialogs 1.2
import QtQuick.Window 2.3
import Qt.labs.settings 1.0
import MuseScore 3.0

MuseScore {

    menuPath: "Plugins." + qsTr("Export practice files (multivox)")
    version: "0.0.0"
    requiresScore: true
    pluginType: "dialog"
    id: multivox
    description: qsTr("Export score as PDF, Midi, MusicXML and individual staff MP3s.")

    Component.onCompleted: {
        if (mscoreMajorVersion >= 4) {
            multivox.title = qsTr("Export score as PDF, Midi, MusicXML and individual staff MP3s.");
            multivox.categoryCode = "export";
        }
    }

    Settings {
        id: settings
        category: qsTr("Export practice files")
        property alias volumeFactor: factorSlider.value
        property alias exportFolder: exportFolder.text
    }

    onRun: {
        // Make very sure we have a score
        if (!curScore) {
            return;
        }

        // check MuseScore version
        if (mscoreMajorVersion != 3 ||
            mscoreMinorVersion != 6) {
            multivox.visible = false;
            versionError.open();
            return;
        }

    }

    // Layout based on https://musescore.org/en/node/345584#comment-1177229

    // Compute dimension based on content
    width: exportDialog.implicitWidth + extraLeft + extraRight
    height: exportDialog.implicitHeight + extraTop + extraBottom

    property int extraMargin: exportDialog.anchors.margins ? exportDialog.anchors.margins : 0
    property int extraTop: exportDialog.anchors.topMargin ? exportDialog.anchors.topMargin : extraMargin
    property int extraBottom: exportDialog.anchors.bottomMargin ? exportDialog.anchors.bottomMargin : extraMargin
    property int extraLeft: exportDialog.anchors.leftMargin ? exportDialog.anchors.leftMargin : extraMargin
    property int extraRight: exportDialog.anchors.rightMargin ? exportDialog.anchors.rightMargin : extraMargin

    function getCurrentState() {
        var result = [];
        for (var part in curScore.parts) {
            result[part] = [];
            for (var instrument in curScore.parts[part].instruments) {
                result[part][instrument] = [];
                for (var channel in curScore.parts[part].instruments[instrument].channels) {
                    result[part][instrument][channel] = {};
                    result[part][instrument][channel].volume = curScore.parts[part].instruments[instrument].channels[channel].volume;
                    result[part][instrument][channel].midiProgram = curScore.parts[part].instruments[instrument].channels[channel].midiProgram;
                }
            }
        }
        return result;
    }

    function restoreState(state) {
        for (var part in state)
            for (var instrument in state[part])
                for (var channel in state[part][instrument]) {
                    curScore.parts[part].instruments[instrument].channels[channel].volume =
                        state[part][instrument][channel].volume;
                    curScore.parts[part].instruments[instrument].channels[channel].midiProgram =
                        state[part][instrument][channel].midiProgram;
                }
    }

    function debug(obj) {
        if (typeof obj === "object") {
            var properties = "";
            for (var property in obj)
                if (typeof obj[property] === "object")
                    properties += property+": object{}\n";
                else if (typeof obj === "function")
                    properties += property+": function()\n";
                else
                    properties += property+": "+obj[property]+"\n";
            console.log(properties);
        } else if (typeof obj === "function") {
            return "function()";
        }
        console.log(obj);
    }

    function getStaff(staffIdx) {
        // This should just be `curScore.staves[staffIdx]`, but this doesn't 
        // work in 3.6 due to a bug: https://github.com/musescore/MuseScore/pull/7480
        // As a workaround, find an element on the staff and use Element.staff
        var seg = curScore.firstMeasure.firstSegment;
        while (seg != null) {
            // Segment.elementAt() takes a track index.
            // There are 4 tracks per staff, hence the multiplication by 4.
            // (It may be more robust to try the other 3 tracks in the staff as well.)
            var e = seg.elementAt(staffIdx * 4);
            if (e != null) {
                return e.staff;
            }
            seg = seg.next;
        }
    }

    function getFirstNote(chord) {
        for (var noteIdx in chord.notes) {
            if (noteIdx != null) {
                return chord.notes[noteIdx];
            }
        }
        return null;
    }

    function firstStaffForPart(part) {
        for (var staffIdx = 0; staffIdx < curScore.nstaves; staffIdx++) {
            var staff = getStaff(staffIdx);
            if (staff.part.partName == part.partName) {
                return staffIdx;
            }
        }
        return -1;
    }

    function isDominantPart(part) {
        // We don't have a better way to do this
        return part.partName == "Grand Piano";
    }

    function isAccompaniment(part) {
        // We should probably have a better way to do this
        return part.partName == "Piano";
    }

    function getOrCreateDominantStaff() {
        // There appears to be no way to delete a part. So, to avoid adding
        // additional staves whenever the plugin is invoked, stash some
        // state to remember whether we've created the dominant part already.
        // We use a metadata tag for this, and store the index of the dominant
        // part's (first) staff as the associated value.
        var dominantStaffIdx;
        var dominantStaffMetadata = curScore.metaTag("multivoxDominantStaffIdx");
        if (dominantStaffMetadata != "") {
            // We've previously created a dominant part.
            // Look up its staff index.
            dominantStaffIdx = parseInt(dominantStaffMetadata);
        } else {
            // It would be nice to name this part something like "Dominant",
            // but there appears to be no API for doing this.
            curScore.appendPart("grand-piano");        

            // A piano part has two staves. Just use the first one for simplicity.
            dominantStaffIdx = curScore.nstaves - 2;

            curScore.setMetaTag("multivoxDominantStaffIdx", dominantStaffIdx);

            // The addition of the new part needs to be "flushed" with
            // an endCmd/startCmd pair for subsequent actions to see it.
            curScore.endCmd();
            curScore.startCmd();
        }
        return dominantStaffIdx;
    }

    function selectStaffForCopying(staffIdx) {
        // Copying is straightforward: select the entire extent of the staff.
        curScore.selection.selectRange(
            curScore.firstMeasure.firstSegment.tick,
            curScore.lastSegment.tick + 1,
            staffIdx,
            staffIdx + 1);
    }

    function selectStaffForPasting(staffIdx) {
        // Pasting is trickier. Musescore refuses to paste into a type of
        // selection created with Selection.selectRange(). Instead we have
        // to use Selection.select() on the first selectable element.
        var seg = curScore.firstMeasure.firstSegment;
        var firstSelectableElement = null;
        while (seg != null) {
            var e = seg.elementAt(staffIdx * 4);
            if (e != null) {
                if (e.type == Element.REST) {
                    firstSelectableElement = e;
                    break;
                }
                if (e.type == Element.CHORD) {
                    var firstNote = getFirstNote(e);
                    if (firstNote != null) {
                        firstSelectableElement = firstNote;
                        break;
                    }
                }
            }
            seg = seg.next;
        }
        if (firstSelectableElement != null) {
            curScore.selection.select(firstSelectableElement);
            return true;
        }
        return false;
    }

    // Helper function to export a single track.
    // Returns an empty string on success and a string describing what went wrong
    // on failure.
    function exportTrackForPart(part, dominantStaffIdx) {
        // Copy current part to dominant staff
        var staffIdx = firstStaffForPart(part);
        if (staffIdx == -1) {
            return "can't find staff for part";
        }
        selectStaffForCopying(staffIdx);
        cmd("copy");
        if (!selectStaffForPasting(dominantStaffIdx)) {
            return "failed to select dominant staff for pasting";
        }
        cmd("paste");
        curScore.selection.clear();

        // Export part
        writeScore(curScore, exportFolder.text+"/"+baseFileName.text+"-"+part.partName+".mp3", "mp3");
        return "";
    }

    function exportFiles() {
        curScore.startCmd();

        // Export full score
        writeScore(curScore, exportFolder.text+"/"+baseFileName.text+".mp3", "mp3");

        // Get or create the part for the "dominant" track
        var dominantStaffIdx = getOrCreateDominantStaff();

        // Remember current channel volumes and midi programs
        // (Note: the plugin currently only changes volumes, but a previous
        //        version changed midi programs as well and I kept around
        //        the functionality to save and restore both.)
        var state = getCurrentState();

        // Export individual parts as mp3
        for (var partIndex in curScore.parts) {
            var part = curScore.parts[partIndex];

            // Skip piano accompaniment (if any) and dominant part
            if (isAccompaniment(part) || isDominantPart(part)) {
                continue;
            }

            // Lower volume on other parts
            for (var otherPart in state)
                if (otherPart != partIndex && !isDominantPart(curScore.parts[otherPart]))
                    for (var instrument in state[otherPart])
                        for (var channel in state[otherPart][instrument])
                            curScore.parts[otherPart].instruments[instrument].channels[channel].volume *= factorSlider.value/100;

            var error = exportTrackForPart(part, dominantStaffIdx);
            if (error != "") {
                console.log("Error: track for part '" + part.partName + "' was not written: " + error);
            }

            // Restore other parts' volumes and midi programs
            restoreState(state);
        }

        // Clean up by deleting the contents of the dominant staff.
        // This ensures that e.g. if the plugin is invoked again, the full score
        // doesn't have piano notes for the most recently exported part.
        selectStaffForCopying(dominantStaffIdx);
        cmd("delete");
        curScore.selection.clear();

        curScore.endCmd();
        exportFinishedDialog.open();
    }

    ColumnLayout {
        id: exportDialog
        spacing: 2
        anchors.margins: 0

        GridLayout {
            Layout.margins: 20
            Layout.minimumWidth: 250
            Layout.minimumHeight: 100

            columns: 1

            Row {
                Label {
                    anchors.verticalCenter: factorSlider.verticalCenter
                    text: qsTr("Volume for other instruments:")
                }
                Slider {
                    id: factorSlider
                    from: 0
                    to: 100
                    anchors.leftMargin: 4
                    // https://doc.qt.io/qt-5/qtquickcontrols2-customize.html
                    handle: Rectangle {
                        x: factorSlider.leftPadding + factorSlider.visualPosition * (factorSlider.availableWidth - width)
                        y: factorSlider.topPadding + factorSlider.availableHeight / 2 - height / 2
                        implicitWidth: 12
                        implicitHeight: 12
                        radius: 12
                        border.color: "#bdbebf"
                    }
                }
                Label {
                    text: Math.floor(factorSlider.value)+"%"
                    anchors.verticalCenter: factorSlider.verticalCenter
                    anchors.leftMargin: 4
                }
            }

            GridLayout {
                columns: 3

                Label {
                    anchors.verticalCenter: baseFileName.verticalCenter
                    text: qsTr("Base file name:")
                }
                TextField {
                    id: baseFileName
                    anchors.leftMargin: 8
                    validator: RegExpValidator { regExp: /[^\\|/|:|*|?|\"|<|>|\|]+/ }
                    text: curScore.title
                    Layout.columnSpan: 2
                    selectByMouse: true
                    // https://doc.qt.io/qt-5/qtquickcontrols2-customize.html
                    background: Rectangle {
                        implicitWidth: 200
                        implicitHeight: 10
                        border.color: "#bdbebf"
                    }
                }

                Label {
                    anchors.verticalCenter: exportFolder.verticalCenter
                    text: qsTr("Export to folder:")
                }
                TextField {
                    id: exportFolder
                    anchors.leftMargin: 8
                    selectByMouse: true
                    text: decodeURIComponent(curScore.path.replace(/^file:\/\//, "").replace(/\/[^\/]+$/, ""))
                    // https://doc.qt.io/qt-5/qtquickcontrols2-customize.html
                    background: Rectangle {
                        implicitWidth: 200
                        implicitHeight: 10
                        border.color: "#bdbebf"
                    }
                }
                Button {
                    text: qsTr("Browse") + "..."
                    anchors.verticalCenter: exportFolder.verticalCenter
                    onClicked: {
                        exportFolderDialog.folder = Qt.resolvedUrl(exportFolder.text);
                        exportFolderDialog.open();
                    }
                }
            }
        }

        DialogButtonBox {
            Layout.fillWidth: true
            spacing: 5
            alignment: Qt.AlignRight
            background.opacity: 0

            standardButtons: DialogButtonBox.Ok | DialogButtonBox.Cancel

            onAccepted: {
                exportFiles();
                multivox.parent.Window.window.close();
            }

            onRejected: {
                multivox.parent.Window.window.close();
            }

        }
    }

    SystemPalette {
        id: sysActivePalette;
        colorGroup: SystemPalette.Active
    }
    SystemPalette {
        id: sysDisabledPalette;
        colorGroup: SystemPalette.Disabled
    }

    FileDialog {
        id: exportFolderDialog
        title: qsTr("Select target folder")
        selectFolder: true
        folder: Qt.resolvedUrl(exportFolder.text)
        //modality: Qt.platform.os == "osx" ? Qt.NonModal : Qt.WindowModal

        onAccepted: {
            exportFolder.text = exportFolderDialog.folder.toString().replace(/^file:\/\//, "");
        }
        onRejected: {
            console.log("No target folder selected")
        }
    }

    // Version mismatch dialog
    MessageDialog {
        id: versionError
        visible: false
        title: qsTr("Unsupported MuseScore Version")
        text: qsTr("This plugin requires MuseScore 3.6.")
    }

    // Finished export dialog
    MessageDialog {
        id: exportFinishedDialog
        visible: false
        title: qsTr("Finished")
        text: qsTr("Export of practice files has finished.")
        onAccepted: {
            multivox.parent.Window.window.close();
        }
    }

}
