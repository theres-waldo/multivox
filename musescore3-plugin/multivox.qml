import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Dialogs 1.2
import QtQuick.Window 2.3
import Qt.labs.settings 1.0
import MuseScore 3.0

MuseScore {

    menuPath: "Plugins." + qsTr("Export practice files")
    version: "0.0.0"
    requiresScore: true
    pluginType: "dialog"
    id: practiceExport
    description: qsTr("Export score as PDF, Midi, MusicXML and individual staff MP3s.")

    Component.onCompleted: {
        if (mscoreMajorVersion >= 4) {
            practiceExport.title = qsTr("Export score as PDF, Midi, MusicXML and individual staff MP3s.");
            practiceExport.categoryCode = "export";
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
            practiceExport.visible = false;
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

    function getCurrentVolumes() {
        var result = [];
        for (var part in curScore.parts) {
            result[part] = [];
            for (var instrument in curScore.parts[part].instruments) {
                result[part][instrument] = [];
                for (var channel in curScore.parts[part].instruments[instrument].channels) {
                    result[part][instrument][channel] = curScore.parts[part].instruments[instrument].channels[channel].volume;
                }
            }
        }
        return result;
    }

    function restoreVolumes(volumes) {
        for (var part in volumes)
            for (var instrument in volumes[part])
                for (var channel in volumes[part][instrument])
                    curScore.parts[part].instruments[instrument].channels[channel].volume =
                        volumes[part][instrument][channel];
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

    function exportFiles() {
        curScore.startCmd();

        // Remember current channel volumes
        var volumes = getCurrentVolumes();

        // Export full score
        writeScore(curScore, exportFolder.text+"/"+baseFileName.text+".pdf", "pdf");
        writeScore(curScore, exportFolder.text+"/"+baseFileName.text+".mid", "mid");
        writeScore(curScore, exportFolder.text+"/"+baseFileName.text+".musicxml", "musicxml");
        writeScore(curScore, exportFolder.text+"/"+baseFileName.text+".mp3", "mp3");

        // Export other excerpts as pdf
        for (var excerpt in curScore.excerpts)
            writeScore(curScore.excerpts[excerpt].partScore, exportFolder.text+"/"+baseFileName.text+"-"+curScore.excerpts[excerpt].title+".pdf", "pdf");

        // Export individual parts as mp3
        for (var part in curScore.parts) {
            // Silence the other parts
            for (var otherPart in volumes)
                if (otherPart != part)
                    for (var instrument in volumes[otherPart])
                        for (var channel in volumes[otherPart][instrument])
                            curScore.parts[otherPart].instruments[instrument].channels[channel].volume *= factorSlider.value/100;
            // Export part
            writeScore(curScore, exportFolder.text+"/"+baseFileName.text+"-"+curScore.parts[part].partName+".mp3", "mp3");
            // Restore other parts volumes
            restoreVolumes(volumes);
        }

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
                practiceExport.parent.Window.window.close();
            }

            onRejected: {
                practiceExport.parent.Window.window.close();
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
            practiceExport.parent.Window.window.close();
        }
    }

}
