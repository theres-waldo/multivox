import MuseScore 3.0
MuseScore {
    // menuPath: "Plugins.multivox"
    description: "Generate mp3 practice tracks for choral music"
    version: "1.0"

    function dump(obj) {
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

    onRun: {
      if (!curScore) {
        console.log("No score, exiting");
        return;
      }

      curScore.startCmd();
      var firstPart = true;
      for (var part of curScore.parts) {
        console.log("Found part '" + part.partName + "' with instrumentId '" + part.instrumentId + "'");
        for (var instrument of part.instruments) {
          console.log("  Found instrument with id '" + instrument.instrumentId + "'");
          for (var channel of instrument.channels) {
            console.log("    Found channel with MIDI program '" + channel.midiProgram + "'");
            // dump(channel);
            if (firstPart) {
              console.log("    --> This is the first part, leaving alone");
              firstPart = false;
            } else {
              console.log("    --> This is not the first part, muting");
              channel.volume = 10;
              channel.midiProgram = 42;
              // channel.mute = true;
            }
          }
        }
      }

      console.log("Now exporting as mp3");
      writeScore(curScore, "/home/botond/ms-exported.mp3", "mp3");
      console.log("Done exporting");
      
      curScore.endCmd();
    }
}
