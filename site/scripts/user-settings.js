$(function () {

    $("#track-definitions").accordion({ heightStyle: 'content', collapsible: true, active: false });
    $("#new-time-track + div textarea").change(function () {
        var text, header = $(this).parents("div").prev();
        console.log("Here you are:");
        if ( this.value.match(/"name"\s*:\s*"([^"]+)/) ) {
           text = RegExp.$1;
           header.find(".name").text("[" + text + "]");
        }
        else alert("No name defined");
        if ( this.value.match(/"label"\s*:\s*"([^"]+)/) ) {
           text = RegExp.$1;
           header.find(".title").text(text);
        }
        else alert("No label defined");
    });
    $("#set-email").click(function () {
        var f = $('#email');
        if ( this.checked ) {
            $('#contact').removeAttr('disabled');
            f.val(f.data("old"));
        }
        else {
            $('#contact').prop('disabled','disabled');
            f.data("old", f.val()).val('(deleted)');
        }
    });
    $("#change-password").click(function () {
        var fieldset = $('#change-password-fieldset');
        if ( this.checked ) {
            fieldset.removeAttr('disabled');
        }
        else {
            fieldset.prop('disabled','disabled');
        }    
        fieldset.toggle(50);
    });
    $("#create-track-btn").click(function () {
       var trackdef = $("#new-time-track").add("#new-time-track + div").clone(true);
       trackdef.first().show().removeAttr("id").end()
           .insertBefore("#new-time-track").first().click().end()
           .find("textarea").focus();
       return false;
    });

    function WeekPattern (definitionString, onUpdateCallback) {

        var table = $('<table class="week-pattern"><tr><th>Work?</th>'
            + '<th><abbr title="Monday">Mo</abbr></th>'
            + '<th><abbr title="Tuesday">Tu</abbr></th>'
            + '<th><abbr title="Wednesday">We</abbr></th>'
            + '<th><abbr title="Thursday">Th</abbr></th>'
            + '<th><abbr title="Friday">Fr</abbr></th>'
            + '<th><abbr title="Saturday">Sa</abbr></th>'
            + '<th><abbr title="Sunday">Su</abbr></th>'
            + '<th>Times</th>'
            + '</tr></table>'
            ),
            rotators = []
            ;

        function update () {

            var string = rotators
                .map(function (a) {
                    return a.interval ? a.serialize() : undefined;
                 })
                .filter(function (a) { return a !== undefined })
                .join(";");

            onUpdateCallback(string);

        }

        function addWeekPatternRotator (ds, baserow) {

            var wpa = new WeekPatternRotator(ds, update),
                tailrow = wpa.tailrow(),
                elements_to_add =
                    wpa.rows.map(function (r) { return r.tr }),
                button = $("<button>+ Week Pattern Rotator</button>");
                ;

            rotators.push(wpa);
            elements_to_add.push(tailrow);

            if ( baserow === undefined ) table.append( elements_to_add );
            else baserow.after( elements_to_add );

            tailrow.find("button").after(button);

            button.click(function (e) {
                e.preventDefault();
                addWeekPatternRotator("", tailrow);
            });

        }

        definitionString.split(";").forEach(
            function (ds) {
                addWeekPatternRotator(ds);
            }
        );

        table.data('rotators', rotators);
        
        return table;

    }

    function WeekPatternRotator (definitionString, onUpdateCallback) {

        var head = $(
            '<tr class="wpahead"><td colspan="9">                            '
          + '   To calendar week nos. of interval <input class="interval" '
          + '   type="number" min="0" value="1"> / shift <input type="number" '
          + '   class="shift" value="0">, i.e. to nos. <strong class="weeks">'
          + '   </strong>, the following pattern(s) apply except superseded  '
          + '   by some pattern of larger interval or shift:</td></tr>'
        );

        var self = {
            interval: 1,
            shift: 0,
            serialize: function () {
                this.dropInnerSpareRows();
                var shift = this.shift,
                    header,
                    strows = this.rows.map(
                        function (r) { return r.calculate(); }
                    );
                strows.shift();
                if ( shift > 0 ) shift = "+" + shift;
                else if ( !shift ) shift = "";
                header = this.interval + "n" + shift;
                if ( header == "1n" ) header = "";
                else header += ":";
                if ( strows[ strows.length-1 ].match(/^\W/) ) strows.pop();
                return header + strows.join(",");
            },

            week_selection: function () {

                var tail = 1, head = 2, i = this.interval, s = this.shift,
                    weeks = Array.apply(0, Array(53))
                        .map(function (x, y) { return y + 1 })
                        .filter(function (w) {
                            w -= s;
                            return w > 0 && w < 54 && !(w % i);
                         }),
                    middle
                    ;

                if ( weeks[ weeks.length -1 ] == 53 ) {
                    weeks[ weeks.length -1 ] = "(53)";
                    tail++;
                }

                if ( weeks.length > 3 ) {
                    middle = weeks.splice(2, weeks.length - head - tail)
                        .join(", ")
                        ;
                    weeks.splice(
                        2, 0, '<span title="' + middle + '">...</span>'
                    );
                }

                return weeks.join(", ");
            },
            rows: [{ tr: head, calculate: function () { return ""; } }],
            dropInnerSpareRows: function () {
                this.rows = this.rows.filter( function (r) {
                    var tr = r.tr;
                    if ( r.calculate().indexOf("-@") == 0 && tr.next() ) {
                        tr.hide("fast", function () { $(this).remove(); });
                    }
                    else return true;
                })
            },
            tailrow: function () {
                var tr = $("<tr><td colspan='9'>"
                    + "<button>+ Week Pattern Row</button>"
                    + "</td></tr>"
                );
                tr.find("button").click(function (e) {
                    e.preventDefault();
                    var rows = self.rows,
                        newrow = new WeekPatternRow(undefined, onUpdateCallback);
                    rows.push(newrow);
                    tr.before(newrow.tr);
                });
                return tr;
            },
        };

        function updateWeekSelection () {
            head.find(".weeks").html(self.week_selection());
        }
        head.find(":input").on('change', function (e) {
            self[this.className] = parseInt(this.value);
            updateWeekSelection();
            onUpdateCallback();
        });
        

        var truncated = definitionString.replace(/^0*(\d+)n([-+]\d+)?:/, "");
        if ( truncated != definitionString ) {
            self.interval = parseInt(RegExp.$1);
            self.shift = parseInt(RegExp.$2) || 0;
        }

        updateWeekSelection();
        head.find(".interval, .shift").each(function () {
            $(this).val(self[this.className]);
        })

        var defPieces = truncated.length
            ? (truncated.match(/([A-Za-z,-]+@\!?\d[0-9:,!-]*)(?:,|$)/g))
                .map(function (p) { return p.replace(/,$/, "") })
            : [undefined]
            ;

        defPieces.forEach(function (s) {
            var row = new WeekPatternRow(s, onUpdateCallback);
            self.rows.push(row);
        });
            
        return self;

    }

    var wdstrings = [
      "-","Mo","Tu","Mo-Tu","We","Mo,We","Tu-We","Mo-We","Th","Mo,Th","Tu,Th",
      "Mo-Tu,Th","We-Th","Mo,We-Th","Tu-Th","Mo-Th","Fr","Mo,Fr","Tu,Fr",
      "Mo-Tu,Fr","We,Fr","Mo,We,Fr","Tu-We,Fr","Mo-We,Fr","Th-Fr","Mo,Th-Fr",
      "Tu,Th-Fr","Mo-Tu,Th-Fr","We-Fr","Mo,We-Fr","Tu-Fr","Mo-Fr","Sa","Mo,Sa",
      "Tu,Sa","Mo-Tu,Sa","We,Sa","Mo,We,Sa","Tu-We,Sa","Mo-We,Sa","Th,Sa",
      "Mo,Th,Sa","Tu,Th,Sa","Mo-Tu,Th,Sa","We-Th,Sa","Mo,We-Th,Sa","Tu-Th,Sa",
      "Mo-Th,Sa","Fr-Sa","Mo,Fr-Sa","Tu,Fr-Sa","Mo-Tu,Fr-Sa","We,Fr-Sa",
      "Mo,We,Fr-Sa","Tu-We,Fr-Sa","Mo-We,Fr-Sa","Th-Sa","Mo,Th-Sa","Tu,Th-Sa",
      "Mo-Tu,Th-Sa","We-Sa","Mo,We-Sa","Tu-Sa","Mo-Sa","Su","Su-Mo","Tu,Su",
      "Su-Tu","We,Su","We,Su-Mo","Tu-We,Su","Su-We","Th,Su","Th,Su-Mo",
      "Tu,Th,Su","Th,Su-Tu","We-Th,Su","We-Th,Su-Mo","Tu-Th,Su","Su-Th",
      "Fr,Su","Fr,Su-Mo","Tu,Fr,Su","Fr,Su-Tu","We,Fr,Su","We,Fr,Su-Mo",
      "Tu-We,Fr,Su","Mo-We,Fr,Su","Th-Fr,Su","Th-Fr,Su-Mo","Tu,Th-Fr,Su",
      "Th-Fr,Su-Tu","We-Fr,Su","We-Fr,Su-Mo","Tu-Fr,Su","Mo-Fr,Su","Sa-Su",
      "Sa-Mo","Tu,Sa-Su","Sa-Tu","We,Sa-Su","We,Sa-Mo","Tu-We,Sa-Su","Sa-We",
      "Th,Sa-Su","Th,Sa-Mo","Tu,Th,Sa-Su","Th,Sa-Tu","We-Th,Sa-Su",
      "We-Th,Sa-Mo","Tu-Th,Sa-Su","Sa-Th","Fr-Su","Fr-Mo", "Tu,Fr-Su","Fr-Tu",
      "We,Fr-Su","We,Fr-Mo","Tu,Fr-Su","Fr-We","Th-Su","Th-Mo","Tu,Th-Su",
      "Th-Tu","We-Su","We-Mo","Tu-Su","Mo-Su"
    ];

    var wdnums = {
        'Mo': 1, 'Mo-Tu': 3, 'Mo-We': 7, 'Mo-Th': 15, 'Mo-Fr': 31, 'Mo-Sa': 63,
        'Mo-Su': 127, 'Tu': 2, 'Tu-We': 6, 'Tu-Th': 14, 'Tu-Fr': 30,
        'Tu-Sa': 62, 'Tu-Su': 126, 'Tu-Mo': 127, 'We': 4, 'We-Th': 12,
        'We-Fr': 28, 'We-Sa': 60, 'We-Su': 124, 'We-Mo': 125, 'We-Tu': 127,
        'Th': 8, 'Th-Fr': 24, 'Th-Sa': 56, 'Th-Su': 120, 'Th-Mo': 121,
        'Th-Tu': 123, 'Th-We': 127, 'Fr': 16, 'Fr-Sa': 48, 'Fr-Su': 112,
        'Fr-Mo': 113, 'Fr-Tu': 115, 'Fr-We': 119, 'Fr-Th': 127, 'Sa': 32,
        'Sa-Su': 96, 'Sa-Mo': 97, 'Sa-Tu': 99, 'Sa-We': 103, 'Sa-Th': 111,
        'Sa-Fr': 127, 'Su': 64, 'Su-Mo': 65, 'Su-Tu': 67, 'Su-We': 71,
        'Su-Tu': 79, 'Su-Fr': 95, 'Su-Sa': 127,
    };

    function wdstr_to_num (wdstr) {
        var nums = wdstr.split(",").map( function (i) { return wdnums[i]; } ),
            sum = 0;
        nums.forEach(function (i) { sum += i; })
        return sum;
    }

    function WeekPatternRow (initialString, onUpdateCallback) {
    
        var tr = this.tr = $(
            '<tr class="week_days">'
          + '   <td class="work"><input type="checkbox"></td>             '
          + '   <td class="wd Mo"><input type="checkbox" value="1"></td>  '
          + '   <td class="wd Tu"><input type="checkbox" value="2"></td>  '
          + '   <td class="wd We"><input type="checkbox" value="4"></td>  '
          + '   <td class="wd Th"><input type="checkbox" value="8"></td>  '
          + '   <td class="wd Fr"><input type="checkbox" value="16"></td> '
          + '   <td class="wd Sa"><input type="checkbox" value="32"></td> '
          + '   <td class="wd Su"><input type="checkbox" value="64"></td> '
          + '   <td class="times"><input size=10 type="text"></td></tr>   '
        );

        var calculated = "";

        function normalized_times (work, times) {
            // If work is checked, leave, else invert all exclusions
            return times.replace(/(^|,)(!?)/g, function (excl) {
                return RegExp.$1 + (( RegExp.$2 ? work : !work ) ? "!" : "");
            });
        }

        function assemble () {
            var work = tr.find(".work input")[0].checked;
            var times = normalized_times(
                work,
                tr.find(".times input").val()
            );

            calculated = wdstrings[ tr.data("decimal_dayseq") ] + "@" + times;

            return true;

        }

        function updater () { return assemble() && onUpdateCallback(); }

        tr.find(".work input").click(function () { return updater() });

        tr.find(".wd input").click(function(e) {
            var value = this.value;
            value *= ( this.checked ) ? 1 : -1;
            value += tr.data("decimal_dayseq"); 
            tr.data("decimal_dayseq", value);
            return updater();
        });

        tr.find(".times input").change(function (e) {
            var field = $(this), components = field.val().split(","), pc, R = RegExp;
            while ( pc = components.shift() ) {
                if (/^!?(\d?\d)(:(\d\d)(?=-))?(-(\d?\d)(:(\d\d))?)?$/.test(pc)) {

                    if (!(                  parseInt(R.$1) < 24
                        && ( R.$3.length ? parseInt(R.$3) < 60 : 1 )
                        && ( R.$5.length ? parseInt(R.$5) < 24 : 1 )
                        && ( R.$7.length ? parseInt(R.$7) < 60 : 1 )
                       )) {
                        alert("Invalid day-time in '" + pc
                            + "'! (0-23 hours, 0-59 minutes)");
                        setTimeout(function () { field.focus() }, 0);
                        return;
                    }

                }
                else {

                    alert("Invalid input '" + pc + "'.\n\n"
                      +"It must have the following format:\n"
                      +" - 0-23 to indicate (from) which hour\n"
                      +" - (optional) :00 to 59 to indicate from which minute\n"
                      +" - (optional) -HH or -HH:MM to indicate until when\n"
                      +"   Without until-part, only indicate the hour.\n"
                      +"   Please note: without :MM, the full hour applies.\n"
                    );
                    setTimeout(function () { field.focus() }, 0);
                    return;

                }
            }
            return updater();
        });

        (function (str) {
            tr.data("decimal_dayseq", 0);
            if ( str === undefined ) return;
            var strp = str.split('@'),
                otimes = strp[1].replace(/(!?)/, ""),
                work = !RegExp.$1.length,
                times = normalized_times(work, otimes),
                num = wdstr_to_num(strp[0]),
                week_row = tr.find(".wd input");
            tr.data("decimal_dayseq", num);
            [6,5,4,3,2,1,0].forEach(function (i) {
                var n = Math.pow(2, i);
                if ( num >= n ) { num -= n; week_row[i].checked = true; }
                else week_row[i].checked = false;
            });
            tr.find(".times input").val(times);
            tr.find(".work input")[0].checked = work;
            assemble();
        })(initialString);

        this.calculate = function () { return calculated };

    }

    /*
    $("#week-pattern-source").change(function () {
        function update (string) { source.val(string); }
        var source = $(this), oldtable = source.next(),
            instance = new WeekPattern( source.val(), update );
        if ( oldtable ) oldtable.remove();
        instance.insertAfter(source);
    });
    */

    var addVariationDialog = $('#add-variation-dialog'),
        textField = function (f, updater) {
            f.removeAttr("readonly");
            f.change(function () { updater(this.value) });
        },
        selectFromMenu = function (f, updater, values) {
            var menu = $("<select>"), cur, label, selected;
            for ( var v in values ) {
                selected = values[v] == f.val() ? 'selected="selected"' : '';
                $('<option value="' + v + '" '
                    + selected + '>' + values[v] + '</option>'
                ).appendTo(menu).click(function () { updater(this.value) });
            }
            f.replaceWith(menu);
        },
        inherit_modes = {
            "optional": "optional, i.e. ignored unless 'ref'erenced explicitly",
            "suggest": "suggest, induce between middle and bottom variations",
            "impose": "impose, induce between middle and top variations"
        },
        fieldtypes = {
            label: textField,
            description: textField,
            unmentioned_variations_from: textField,
            from_date: function (f, updater) {
                FlowgencyTM.DateTimePicker.apply(f);
                f.removeAttr("readonly");
                f.change(function () { updater(this.value) });
            },
            from_earliest: function (f, updater) {
                FlowgencyTM.DateTimePicker.apply(f);
                f.removeAttr("readonly");
                f.change(function () { updater(this.value) });
            },
            until_date: function (f, updater) {
                f.addClass("until");
                f.removeAttr("readonly");
                FlowgencyTM.DateTimePicker.apply(f);
                f.change(function () { updater(this.value) });
            },
            until_latest: function (f, updater) {
                f.addClass("until");
                f.removeAttr("readonly");
                FlowgencyTM.DateTimePicker.apply(f);
                f.change(function () { updater(this.value) });
            },
            successor: textField,
            week_pattern_of_track: textField,
            week_pattern: function (f, updater) {
                var preset = f.val(),
                    instance = new WeekPattern(preset, updater);
                f.replaceWith(instance);
            },
            section_of_track: textField,
            apply: function (f, updater) {
                return selectFromMenu(f, updater, {
                    "middle": "in the middle between suggest and imposed inherited variations",
                    "bottom": "bottom, below suggested variations",
                    "top":"top, above imposed variations",
                    "ignore": "ignore variation (delete unless inherited)"
                });
            },
            inherit_mode: function (f, updater) {
                return selectFromMenu(f, updater, inherit_modes );
            },
            default_inherit_mode: function (f, updater) {
                return selectFromMenu(f, updater, inherit_modes );
            },
        },
        mainFields = [
            'week_pattern', 'week_pattern_of_track', 'unmentioned_variations_from',
            'label', 'default_inherit_mode', 'from_earliest', 'successor', 'until_latest'
        ],
        varFields = [
            'week_pattern', 'week_pattern_of_track', 'section_of_track', 'description', 'ref', 'apply',
            'until_date', 'from_date', 'inherit_mode'
        ],
        tabTemplate = "<li><a href='#{href}'>#{label}</a> <span class='ui-icon ui-icon-close' role='presentation'>Remove Tab</span></li>";
    ;

    function setup_field(field, proxy) {
        var key = field.data("property"),
            fsetLegend = field.closest("fieldset").children("legend");
        $('<input title="toggle field definition" type="checkbox" checked="checked">')
            .click(function () {
                 var fs = $(this).closest("fieldset");
                 fs.prop("disabled", this.checked ? null : "disabled" );
            }).appendTo(fsetLegend);
        fsetLegend.wrapInner("<label>"); 
        function updater (value) {
            if ( value === undefined ) value = this.val();
            if ( value === null ) proxy.drop(key);
            else proxy[key] = value;
            console.log("Changed key " + key + " to value " + value);
            proxy._docker();
        }
        return fieldtypes[ key ](field, updater);
    }

    $(".vtab").each(function () {
       var vtab = $(this), ul = $('<ul>'), dialog, trackdata = {};

       function dynamize(tab, name, isMain) {
           var fields = isMain ? mainFields : varFields,
               properties = { _docker: function () {} },
               proxy = new FlowgencyTM.ObjectCacheProxy(properties, name, fields);
           tab.find("input.property").each(function () { return setup_field( $(this), proxy  ); });
           tab.find("fieldset.undefined option").click(function () {
               var option = $(this), fieldname = option.text(),
                   field = $('<input class="property">'), fieldset;
               if ( option.attr('value') == "" ) return;
               $('<fieldset><legend>'+fieldname+'</legend></fieldset>')
                   .append(field).insertBefore(option.closest(".undefined"));
               field.data("property", fieldname);
               setup_field(field, proxy);
               option.prop("disabled", "disabled");
           });
           if ( isMain ) {
               properties.variations = [null]; /* null means "append" */
               properties.name = name.split("/")[1];
               trackdata = properties;
           }
           else {
               properties._docker = function () {
                   trackdata.variations.push(properties);
                   this._docker = function () {};
               }
           }
       }

       vtab.children("div").each(function () {
          var id = $(this).attr('id'), name, li = $('<li><a>'), isMain = false;
          if ( isMain = id.indexOf("-fill-in") > 0 ) {
              name = "MAIN";
          }
          else name = id.replace(/(\w+)-variation-/, '');
          li.children().text(name).attr('href', '#' + id);
          ul.append(li);
          dynamize($(this), isMain ? id.split("-")[0] : RegExp.$1 + "/" + name, isMain);
       });

       vtab.prepend(ul);
       vtab.tabs().addClass( "ui-tabs-vertical ui-helper-clearfix" );
       vtab.find('li').removeClass( "ui-corner-top" ).addClass( "ui-corner-left" );

       function addVariation () {
           var label = $("#new-variation-name").val(),
               id = "tabs-" + tabCounter,
               li = $( tabTemplate.replace( /#\{href\}/g, "#" + id ).replace( /#\{label\}/g, label ) ),
               new_vtab = addVariationDialog.find(".vtab").clone();
           dynamize(new_vtab, "/" + label, false);
           vtab.find( ".ui-tabs-nav" ).append( li );
           vtab.append( new_vtab );
           vtab.tabs( "refresh" );
       }
 
       dialog = addVariationDialog.dialog({
           autoOpen: false,
           modal: true,
           buttons: {
               Add: function() {
                   addVariation();
                   $( this ).dialog( "close" );
               },
               Cancel: function() {
                   $( this ).dialog( "close" );
               }
           },
           close: function () {
               $(this).find("form").reset();
           }   
       });
       addVariationDialog.find( "form" ).submit(function( event ) {
          addTab();
          dialog.dialog( "close" );
          event.preventDefault();
       });
       vtab.data("trackdata", trackdata);
    });
    $(".vtab").delegate( "span.ui-icon-close", "click", function() {
       var panelId = $( this ).closest( "li" ).remove().attr( "aria-controls" );
       $( "#" + panelId ).remove();
       trackdata.variations.push({ ref: panelId, apply: false });
       vtab.tabs( "refresh" );
    });

    $("#update-settings-form").submit(function () {
       var time_model_data = {};
       $("#configure-time-model .vtab").each(function () {
           var trackdata = $(this).data("trackdata");
           if ( trackdata === undefined ) return;
           
       });
    });

});
