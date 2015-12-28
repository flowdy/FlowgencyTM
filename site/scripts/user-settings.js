$(function () {

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

    var mainFields = [
            'label', 'week_pattern', 'week_pattern_of_track', 'unmentioned_variations_from',
            'force_receive_mode', 'default_inherit_mode', 'from_earliest', 'successor', 'until_latest'
        ],
        varFields = [
            'description', 'week_pattern', 'week_pattern_of_track', 'section_of_track', 'ref',
            'from_date', 'until_date', 'apply', 'inherit_mode'
        ],
        tabTemplate = "<li><a href='#{href}'>#{label}</a> <span class='ui-icon ui-icon-close' role='presentation'>Remove Tab</span></li>";
    ;

    var ul = $('<ul>').prependTo("#track-definitions");

    
    var tm_prototype_initializers = (function () {

        function text (value, block) {
            var input = block.find("input");
            if ( value.length ) input.val(value);
            return function () { return input.val(); };
        }

        function radio (value, block) {
            var new_value;
            block.find("input:radio").filter("[value=" + value + "]").click().end()
                .prop("name", "tmp-radio").click(function () { new_value = $(this).val(); });
            return function () { return new_value; };
        }

        function date (value, block) {
            var input = block.find("input");
            input.val(value);
            FlowgencyTM.DateTimePicker.apply(input,[true]);
            return function () { return input.val() };
        }

        function track (value, block) {
            var selector = $("<select>");

            $.each(get_tracks(), function (name, title) {
                selector.append('<option value="' + name + '">' + title + "</option>");
            });

            block.find("input").replaceWith(selector);
            selector.find("[value=" + value + "]").prop("selected", "selected");

            return function () { return selector.find(":selected").val(); };
        }

        var variation = text; // todo
        return {
            label: text,
            week_pattern: function (value, block) {
                var new_value;
                block.find("input").replaceWith(
                    new WeekPattern(value, function (v) { new_value = v; })
                );
                return function () { return new_value; }
            },
            week_pattern_of_track: track,
            default_inherit_mode: radio,
            force_receive_mode: radio,
            unmentioned_variations_from: text,
            from_earliest: date, from_date: date,
            until_earliest: date, until_date: date,
            successor: track,
            description: text,
            section_of_track: track,
            ref: variation,
            apply: radio,
            inherit_mode: radio
        };

    })();

    $("#track-definitions .vtab").each(function () {
       var vtab = $(this), trackdata;

       var id = vtab.data('name'), li = $('<li><a>');
       li.children().text(id).attr('href', '#track-' + id);
       ul.append(li);

       vtab.prop('id', 'track-' + id);
 
       trackdata = dynamize(vtab.find(".fill-in"), null, id);
       vtab.find(".variations > li").each(function () {
            var variation = $(this);
            dynamize( variation, trackdata, variation.data('name') );
       });

       vtab.data("trackdata", trackdata);
    });

    $("#track-definitions").tabs();

    $("#extend-time-model-name").change(function (e) {
        var nameInput = $(this), name = nameInput.val();
        if ( !name || (name.match(/\W/) ) ) {
            alert("Name " + name + " is invalid");
            setTimeout(function () { nameInput.focus(); }, 10);
        }
    });

    $("#create-track-btn").click(function (e) {
        e.preventDefault();
        var nameInput = $("#extend-time-model-name"), name = nameInput.val(),
            createTrackOkay = true;

        $.each(get_tracks(), function (key) {
            if ( name === key ) {
                alert("The name " + name + " is already used for another track.");
                createTrackOkay = false;
                return false;
            }
            else { return; }
        });

        if ( createTrackOkay ) {
            var newTabHandle = $(tabTemplate.replace(/#\{href\}/, '#track-' + name )
                                    .replace(/#\{label\}/, name )
                         ),
                newTab = $('<div class="vtab">').appendTo("#track-definitions"),
                trackdata;
            newTab.prop('id', 'track-' + name);
            newTab.data('name', name);
            var newTabFillIn = $('<div id="' + name + '-fill-in" class="fill-in future">'
                     + '<div class="undefined-properties" title="Available properties">'
                     + '</div>')
                     .appendTo(newTab);
            var newTabFields = newTabFillIn.find(".undefined-properties");
            $.each(mainFields, function (i, key) {
                newTabFields.append(' <a href="javascript:void(0);">' + key + '</a>');
            });
            trackdata = dynamize(newTabFillIn, null, name);
            newTab.data('trackdata', trackdata);
            var tabs = $("#track-definitions")
            tabs.find(".ui-tabs-nav").append(newTabHandle)
            newTabHandle.find(".ui-icon-close").click(function (e) {
                var panelId = $( this ).closest( "li" ).remove().attr( "aria-controls" );
                $( "#" + panelId ).remove();
                tabs.tabs( "refresh" );
            });
            tabs.tabs( 'refresh' );
        }
        else nameInput.focus();
    });

    $("#add-variation-btn").click(function (e) {
        e.preventDefault();
        var id = $("#track-definitions .ui-state-active a").attr('href'), activeTab = $(id),
            variations = activeTab.find(".variations"),
            nameInput = $(this).parent().find("input:text"),
            name = nameInput.val(), createVariationOkay;
        if ( variations.length ) {
            createVariationOkay = true;
            variations.each(function () {
                if ( $(this).data('name') === name ) {
                    alert("The name " + name + " is already already for another variation in current track.");
                    createVariationOkay = false;
                    return false;
                }
                else { return; }
            });
        }
        else {
            variations = $('<ul class="variations">');
            variations.appendTo(activeTab);
            variations.before('<h3>Variations</h3>');
            createVariationOkay = true;
        }

        if ( createVariationOkay ) {
            var newLi = $('<li class="variation new">').data('name', name)
                        .append('<span><strong class="name">' + name + '</strong>: <span>'),
                fields = $('<div class="undefined-properties" title="Available fields">').appendTo(newLi);
            $.each(varFields, function (i, key) {
                fields.append(' <a href="javascript:void(0);">' + key + '</a>');
            });
            newLi.appendTo(variations);
            dynamize(newLi, activeTab.data('trackdata'), name);
        }
        else nameInput.focus();

    });

    function get_tracks () {
        var tracks = {};
        $("#track-definitions .ui-tabs-nav > li a").each(function () {
            var self = $(this),
                title = self.closest("div").find('#track-' + self.text()).find(".fill-in dfn[title=label]").text();
            tracks[ self.text() ] = title;
        });
        return tracks;
    }   

    function dynamize(tab, trackdata, name) {
        var fields = trackdata ? varFields : mainFields, properties, proxy;

        tab.on("click", ".property, .undefined-properties a", change_track);

        if ( trackdata ) {
            properties = new PropertyCollection(name, trackdata);
        }
        else {
            properties = new PropertyCollection();
            trackdata = properties;
        }

        proxy = new FlowgencyTM.ObjectCacheProxy(name, properties, fields);

        function change_track (e) {
            e.preventDefault();
            var field = $(this), key = field.attr('title') || field.text(),
                variation = field.closest(".variations > li"),
                track = (variation.length ? variation : field).closest(".vtab").data('name'),
                orig_value = field.attr('title') ? field.text() : field.data('orig_value') || '';

            if ( variation ) variation = variation.data('name');

            var mode = variation ? 'variation' : 'track';

            console.log("Changing field " + key + " of track " + track +
                (variation ? ", variation " + variation : '')
            );

            var dialog = $("#configure-timemodel-prototypes").find("."+mode + "." + key)
                    .clone().prependTo("#configure-timemodel-prototypes"),
                init = tm_prototype_initializers[key] || tm_prototype_initializers[mode + " " + key],
                upd = init( proxy[key] || orig_value, dialog, updater ),
                buttons = {
                    "Set": function () {
                        if ( updater(upd()) ) dialog.dialog("close");
                    },
                    "Cancel": function () {
                        dialog.dialog("close");
                    }
                }
            ;
            if ( orig_value.length ) buttons.Reset = function () {
                updater(null);
                dialog.dialog("close");
            }

            var multih;
            if ( multih = dialog.find("header") ) {
                multih = multih.replaceWith( multih.find("p."+key) );
                dialog.prop("title", multih.attr("title"));
                multih.removeAttr("title");
            }
                
            dialog.dialog({
                close: function () {
                    $(this).detach();
                },
                buttons: buttons,
                modal: true,
                width: 500,
                maxHeight: 400,
            });

            function updater (value) {
                var new_field;
                if ( value === undefined ) return false;
                if ( value === null ) {
                    proxy.drop(key);
                    if ( orig_value ) {
                        field.remove();
                        $('<a href="javascript:void(0);">')
                            .text(key).data('orig_value',orig_value)
                            .appendTo(tab.find('.undefined-properties')).before(" ");
                    }
                }
                else {
                    proxy[key] = value;
                    if ( !orig_value.length ) {
                        field.remove();
                        field = $('<dfn class="property">')
                            .text(proxy[key]).prop('title', key);
                        variation ? tab.children().first().after(field) : tab.prepend(field);
                    }
                    else { field.text(proxy[key]); }
                }   
                console.log("Changed key " + key + " to value " + value);
                proxy._docker();
                return true;
            }

        }

        return trackdata;

    }

    function noop () {}

    function PropertyCollection (name, trackdata) {

        var my = this;
        this.name = name;
        if (!trackdata) return;

        this._docker = function () {
            console.log("Added variation " + this.name);
            var t = trackdata;
            if ( !t.variations ) t.variations = [];
            t.variations.push(my);
        }
        
    }
    PropertyCollection.prototype._docker = noop;

    $("#update-settings-form").submit(function () {
       var time_model_data = {};
       $("#configure-time-model .vtab").each(function () {
           var trackdata = $(this).data("trackdata");
           if ( trackdata === undefined ) return;
           time_model_data[ $(this).data('name') ] = trackdata;
       });
       time_model_data = JSON.stringify(time_model_data);
       if ( !time_model_data )
           return;
       if ( confirm("Bitte bestätigen:\n\t" + time_model_data) )
           this.time_model_changes.value = time_model_data;
       else return false;
    });

});
