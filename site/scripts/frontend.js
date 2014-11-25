$(document).ready(function () { new FlowgencyTM(); });

function FlowgencyTM (args) {
   
   var nextload = { update_tasks: {} };

   var get = function (task, step) {
       var task_obj = nextload.update_tasks[task];
       if ( task_obj === undefined )
           nextload.update_tasks[task] = task_obj = { steps: {} };
       if ( step === undefined ) return task_obj;
       var step_obj = task_obj.steps[step];
       if ( step_obj === undefined )
           task_obj.steps[step] = step_obj = {};
       return step_obj;
   };

   var reg_changes = (function () {
       var dirty = false;
       return function (get_only) {
           if ( get_only ) return dirty;
           if ( !dirty ) {
               $("#slogan").text(
                   "<- Please click the logo to commit your changes "
                    + "and get an updated ranking."
               );
               dirty = true;
           }
       };
   })();

   var plans = $("#plans");

   $("#list-opts input").each(function () {
       $(this).click(function () {
           nextload[this.name] ^= this.value;
           console.log("New value of " + this.name + " is " + nextload[this.name]);
       });
   });

   $("#settime").change(function () {
       nextload.now = this.time.value;
       nextload.keep = $(this).find("input[name='keep']:checked").val();
       console.info("Changed time to " + nextload.now + " (keep: " + nextload.keep + ")");
   });

   $.datepicker.setDefaults({ constrainInput: false, dateFormat: 'yy-mm-dd' });

   $("input[type=datetime]").each(function () {
       this.placeholder = '[[[[YY]YY-]MM-]DD] HH:MM';
   }).datetimepicker();

   $("fieldset .fields").accordion({ header: 'dt', heightStyle: 'content' });
   $("form.taskeditor").each(FlowgencyTM.dynamize_taskeditor);

   this.check_done = function (task, step, done) {
       console.log("Checked: " + done);
       step = get(task, step);
       if ( done === undefined )
           delete step["done"];
       else step["done"] = done;
       reg_changes();
   };

   var ftm = this;

   var toggler = function () {
       var plan = $(this);
       var ext = plan.find(".extended-info");
       var task = get(plan.data("id"));
       ext.toggle();
       plan.toggleClass("shadow");
       var isShown = !ext.is(":hidden");
       if ( plan.data("isOpen") != isShown )
           task["open_since"] = isShown ? 'now' : null;
       else delete task["open_since"];
       reg_changes();
   };

   var prepare_plan = function () {
       var plan = $(this);
       var isOpen = plan.find(".extended-info").length;
       plan.data('isOpen', isOpen);
       ftm.progressbar2canvas(plan.find(".progressbar"));
       if ( isOpen ) {
           console.info("Task is already open: "+isOpen);
           ftm.dynamizechecks(plan);
           plan.find("h2").click(toggler.bind(plan));
       }
       else plan.find("h2").click(function () {
           console.info("Open task ...");
           var ext = $(
               '<div class=".extended-info" ><em>Loading ...</em></div>'
           );
           ext.appendTo(plan);
           ext.load("/task/" + plan.data("id") + "/open", function () {
               ftm.dynamizechecks(plan);
           });
           plan.addClass("shadow");
           $(this).die('click').click(toggler);
       });
   };

   plans.children().each(prepare_plan);
 
   $('#logo').click(function (e) {
       var url = '/';
       e.preventDefault();
       var taskeditors = $("form.taskeditor");
       if ( reg_changes(1) || taskeditors.length ) {
           var params = nextload.update_tasks;
           taskeditors.each(function () {
               var task_name = $(this).data('taskid');
               var task = params[task_name] = { steps: {} };
               var changes = $(this).data('changes');
               var root = changes[""];
               delete changes[""];
               Object.keys(changes).forEach(function (i) {
                    task["steps"][i] = changes[i];
               });
               Object.keys(root).forEach(function (i) {
                    task[i] = root[i];
               });
           });
           Object.keys(params).forEach(function (i) {
               params[i] = JSON.stringify(params[i]);
           });
           $.post('/update', params, function () {
               alert("Changes submitted");
               delete nextload.update_tasks;
               url += '?' + $.param(nextload);
           });
       }
       else { 
           url += '?' + $.param(nextload);
       }
       window.location.href = url;
   });

}

FlowgencyTM.prototype.dynamizechecks = function (plan) {
   var ftm = this;
   var checklines = plan.find(".checks");
   var dyn_checkline = function (checkline) {
       return function (e) {
           var check_count,
               previous = this.previousSibling,
               next = this.nextSibling
               ;
           if ( this.checked ) {
               while ( previous && !previous.checked ) {
                   previous.checked = true;
                   previous = previous.previousSibling;
               }
           }
           else {
               while ( next && next.checked ) {
                   next.checked = false;
                   next = next.nextSibling;
               }
           }
           check_count = checkline.children(":checked").length;
           if ( checkline.data('done') == check_count ) check_count = null;
           ftm.check_done( plan.data('id'), checkline.data('id'), check_count );
       };
   };
   console.log("Open task has a checkline: " + checklines.length);
   checklines.each(function () {
       var checkline = $(this);
       checkline.children().each(function () {
           var progressor = dyn_checkline(checkline);
           console.log("attaching progressor...");
           $(this).change(progressor);
       });
   });
   plan.find(".pending-steps li").click(function () {
       $(this).find(":checkbox").not(':checked').first().click();
   });
   plan.find(".pending-steps").find("a, :checkbox").click( function (e) {
       e.stopPropagation();
   });
};

FlowgencyTM.prototype.progressbar2canvas = function (bar) {

   var canvas = document.createElement("canvas"),
       ctx = canvas.getContext('2d'),
       done = bar.children(".erledigt"),
       orient = bar.css("text-align")
   ;

   var saturcolor = done.css("background-color"),
       basecolor = bar.css("background-color"),
       middle = orient == 'left' ?      done.outerWidth() / bar.outerWidth()
              : orient == 'right' ? 1 - done.outerWidth() / bar.outerWidth()
              : null
   ;

   var grSides = orient == 'left' ? [saturcolor, basecolor]
               : orient == 'right' ? [basecolor, saturcolor]
               : []
               ,
       middlecolortransp, middlecolor, gr
   ;

   /* (?:(\d+),){3} *([^)]+) */
   basecolor = basecolor.split(",");
   basecolor[0] = basecolor[0].replace(/^\D+/, "");
   if ( basecolor.length == 4 )
       basecolor[3] = parseFloat(basecolor[3]);
   else if ( basecolor[0] == "" )
       basecolor = [0, 192, 255, 0];
   else basecolor[3] = 1;
   middlecolortransp = (1.0 + basecolor.pop()) / 2.0;
   basecolor = basecolor.map(function(a) {
       return parseInt(a);
   });
   if ( saturcolor.indexOf("rgb") == 0 ) {
       saturcolor = saturcolor.match(/\d+/g).map(function(a) {
           return parseInt(a);
       });
   }
   else if ( saturcolor.indexOf("#") == 0 ) {
       saturcolor = saturcolor.match(/[0-9a-f]{2}/ig).map(function(a) {
           return parseInt(a,16);
       });
   }
   middlecolor = basecolor.map(function(v,i) {
       return parseInt((v + saturcolor[i]) / 2);
   });
   middlecolor.push(middlecolortransp);
   middlecolor = 'rgba(' + middlecolor.join(",") + ')';
   canvas.height = bar.outerHeight();
   canvas.width = bar.outerWidth();
   gr = ctx.createLinearGradient(0,0,canvas.width,0);
   if ( middle > 0 ) gr.addColorStop(0.0, grSides[0]);
   gr.addColorStop(middle, middlecolor);
   gr.addColorStop(1.0, grSides[1]);
   ctx.fillStyle = gr;
   ctx.fillRect(0,0,canvas.width, canvas.height);
   $(canvas).attr('title', bar.attr('title') );
   bar.replaceWith(canvas);
};

FlowgencyTM.dynamize_taskeditor = function () {
    var te = $(this);
    te.data('changes', {});
    te.find('fieldset').each(function () {
        FlowgencyTM.dynamize_taskeditor_step_fieldset($(this));
    });
    $(te.step).change(function () {
        te.find("fieldset").hide();
        $("#step-"+this.value).show();
        window.scrollTo(0,0);
        this.blur();
    });
};

FlowgencyTM.dynamize_taskeditor_step_fieldset = function (fieldset) {
    var step_name = fieldset.attr('id').replace("step-","");
    var changes = fieldset.parent().data('changes');
    var step_changes = changes[step_name];
    if ( !step_changes ) step_changes = changes[step_name] = {};
    var update = function (field) {
        if ( field.defaultValue == field.value )
            delete step_changes[field.name];
        else step_changes[field.name] = field.value;
        console.info("Changed field " + field.name + " for step "
            + step_name + ". Current updates: " 
            + JSON.stringify(changes)
        )
    };
    var closure_cache = {};
    fieldset.find("input[name=priority]").change(function () {
        var numberfield = $(this).parents(".input").children().last();
        if ( this.value ) $(numberfield).val(this.value);
        update(this);
    });
    fieldset.find("p.input:has(input[name=priority]) input:last")
        .focus(function () {
            this.previousSibling.checked = true;
        })
        .change(function () {
            this.previousSibling.value = this.value;
            $(this.previousSibling).change();
        });
    fieldset.find("input[name=checks]").change( function () {
        this.parentNode.lastChild.max = this.value;
        update(this);
    });
    // to add: time stages, substeps
    ['title', 'description', 'done', 'from_date', 'expoftime_share']
       .forEach(function (field) {
            console.info("Setting updater for field " + field + "...");
            fieldset.find("[name="+field+"]").change( function () {
                update(this);
            });
       });
};
