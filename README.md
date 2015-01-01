README (or the [german version](LIESMICH.md))
=============================================

![Logo](site/logo/flowgencytm.png)

What is FlowgencyTM? - Seven key-notes
--------------------------------------

 1. FlowgencyTM is a tool to plan and to manage tasks, their urgencies, progresses and also dependencies if any, just for yourself. In a business world that is fallen for the multitasking illusion, it is essential to maintain atomic steps in a sequential order that allows for completing all of your tasks in time. Doing this all in mind wastes attentiveness and is prone to airy and impulsive revisioning. Better delegate consideration of which tasks deserve your attention most, by right now, to the computer. Provided the data you enter is appropriate, flow experience is then liklier to come, your working gets healthier and more sustainable.

 2. The user interface is implemented in HTML5 and Javascript, so it runs in your favourite web browser. The server component is included in the distribution, too. It is preconfigured to run on your local system from which it exclusively accepts requests.

 3. The tasks are ranked by descending urgency. The ranking is updated when you click the Flowgency logo in the top left edge. You decide when any checks are committed and when you are mentally prepared for being occasionally confronted with other tasks that may have become suddenly more urgent than those you have just been working on.

 4. In FlowgencyTM terms, priority is just one of several urgency dimensions, albeit the only that is directly entered and adjustable afterwards. The software distinguishes four other that depend on time:

   * How close the due-date has approached,

   * how much time has elapsed in relation to how much expenditure you have checked as done,

   * for how much time you have been keeping the task open (if at all) and finally

   * how much will the additional time need be compared to what you have originally planned, considering your working speed.

   You can weight all dimensions as you find appropriate. By default, all five are weighted equally (1).

 5. These four dimensions aforementioned increase with the passage of time. Here, however, "time" is not directly what the system clock measures. FlowgencyTM has got its own that runs or stands still depending on your time model specified in advance. The time model can include both regular and once-only periods of working or off-time and can also distinguish different types of tasks. Pausing tasks are by default even hidden from display.

 6. You can divide tasks into steps, steps again into substeps. You can build arbitrarily deep hierarchies. Sometimes tasks or steps have substeps you find ridiculous to describe because they go without saying. Then you can instead specify that the software is to provide how many checks ever for them, one for each substep just thought.

 7. It is open source software licensed under the General Public License, version 3 or any later version. It resides on GitHub (URL: https://github.com/flowdy/FlowgencyTM) for you to download and use, or to fork it.

This is how FlowgencyTM looks like on your screen:

![Screenshot](doc/snapshot-home.png)

What it is not
--------------

### FlowgencyTM is no groupware

It is not meant for more than small-scale project management, ignoring management of costs, assets, staff, risks etc. Neither as an enterprise-level groupware solution, albeit basic delegation features are planned. You are, however, welcome to enhance it with interfaces to groupware products e.g. for tasks import or the propagation of those done.

### FlowgencyTM has no official smart-phone app

There is no smartphone app in the official FlowgencyTM distribution, because I do not have such a device (seldom missing it) but would need it for testing in development. Hence, to make the official HTML5/Javascript mobile-ready is lowest priority. FlowgencyTM apps you might find someday in your app-store are offered by third parties for any price. Please contact me if you find any GPL v3 violations in a mobile app available in a store, for free or not.

### FlowgencyTM is not unproblematic if served by a third party

Due to its architecture, it is technically possible to provide a FlowgencyTM service for others to click a bookmark and to sign up easily. However, this scenario is not specifically in focus of development. Users of FlowgencyTM are rather encouraged to run their own server to ensure privacy and to elude subtle control. After all a server is simply a program that communicates with other programs via a network interface, which can just as well be `localhost` (IP 127.0.0.1) to ensure that server and client are actually running on the same machine, provided by any system that could likewise communicate with a remote machine via the internet. That way, a FlowgencyTM server listening to a localhost port is as safe against third-party access as the underlying SQLite database and any other file.

FlowgencyTM demo (planned)
--------------------------

It sounds like a contradiction to what is said above, but I encourage everyone who can (and plan myself) to host a FlowgencyTM demo service to let people find out, without having to install software, if the Flowgency tasks & time management concept sufficiently matches their individual working style.

### Available demo sites

(No sites available, yet. If you have deployed an instance to be used under the terms below and you find FlowgencyTM has sufficient multi-user support in place: Just don't hesitate, please send me a link.)

### Conditions of entry in the official list

Every official test and demo site of FlowgencyTM (the "system") must comply to the following conditions:

 1. The system allows use under the explicit restriction that *only fake data may be submitted*, because fake data does not need any privacy or security FlowgencyTM is not designed for ensuring in the first place. To submit data held as a trade secret or underlying some non-disclosure-agreement as well as data that violates or might violate other's rights must be expressedly disallowed. Also point out that all data is stored unencrypted and subject to being viewed and evaluated by the provider.

 2. Users must accept that once they decide for using FlowgencyTM with real and productive data, they have to stop using the system and either install their own server locally if they can, or use a service hosted by someone of competence whom they know and trust personally.

 3. Users must know that their accounts and all associated data are subject to being deleted without notice someday. You can configure a limit of user accounts and adapt it at any time and at your discretion considering server resources to spare.


How best to benefit from using FlowgencyTM
------------------------------------------

### Define your personal time model

User profiles are created with a default 24/7 time model. This is to avoid tasks to vanish at times, thus confusing the user. It is not meant at all to promote the idea that workoholism is of any good.

Your experience of proper urgency-based ranking requires telling the software beforehand when you plan to work on the entered tasks and when not. With FlowgencyTM, you are to plan your working time roughly in advance. You can always modify your time model for the future (e.g. for holidays), but to touch the past would lead to false results which is why that would lead to an error message.

Don't get that wrong: It is not required (practically it is impossible anyway) to follow your defined time model tightly down to the second. Just the more your actual working times match with what you have planned, of the more use will be FlowgencyTM for you. This asks of you some discipline. To a certain extent, you will have to let go of spontaneity, you have to plan your day and to stick. When you have to go no matter what your plans say, you can have a glance into a future state of your urgency ranking left alone till then, so there will be no nasty surprise when you return.

So define: When are you at work? When do you engage in which job or project? And when are you off, absent from work, which means rather fully present for family, friends, hobbies and stuff? When do you want a *computated* reason to let go of worries related to your work organization, business imponderables drawing circles in your mind? Please note, however, that the amount of working time directly relates to how fast urgencies rise along the way.

The time model system is very flexible in order to allow for hopefully everyone's preferences. For example, when you define a variation (a rhythm bound to a given time span) inside a time track, you can have that variation shared with other tracks specified in the track definition. So you need to define holidays only once in a master track, all subordinate "slave" tracks can automatically adopt them and future changes to them as well.

But then there is a risk of overcomplicating your time model. If you don't understand why task X is unlisted as paused suddenly, this is unfavourable and can reduce your productivity by turning your focus back to time management instead of the tasks themselves. Keep it simple and stupid, and do not tune it all the time. Best change it only to add next holidays or when you are imposed / have agreed upon job structure changes.

### Appreciate your off-times

Off does not mean stand-by. You do not need to load and look at FlowgencyTM every now and then. This would be like opening the fridge just to convince yourself that it is dark in there.

### Structure your tasks unless they are simple.<br>Check steps when they are done.

Enter tasks before you do them. Enter even simple ones unless you are certain that doing them right ahead is notably faster than entering them first. In order to enable FlowgencyTM to calculate and rank their urgencies correctly, make sure you take the following questions into consideration:

  * When does a task start if not now, and when is it due?

  * If you have more than one time track, on which do you want to do it?
    That is, when shall they be active and bubbling up in the list in need to be checked? Shall they change the time track at given points in time? Even that is possible, but mind the cost (complexity) versus benefit.

  * Which priorities do they have?

  * Can they be divided into steps and which of those further into substeps perhaps? The hierarchy of steps and substeps can be arbitrarily deep.

  * Do these steps require to be checked in the given or in random order? You can restrict random order to certain subsets of steps. Steps for which you must do other steps first, are not displayed, nor would be those done. You can have also steps to do occasionally in any order, at the latest after having done all ordered steps of a superordinate one or the overall task, respectively.

  * *For advanced users only:* What is the relative expenditure of time of a step compared to other steps surrounding in the hierarchy? The default is 1 and there will not be often a need of adjustment. Do that only when you are certain about it.

  * How many checks do you want to give a specific step/substep? Setting a number greater than 1 is like assigning substeps to it without writing a description, estimating their expenditure of time and maybe increasing the number of checks.

Once a task is entered with proper data, and it is displayed somewhere below in the ranking, just forget it and return to the tasks currently on top.

Check a step right when it is done. When you want to save the checks and you are mentally prepared to switch to another task that might have become more urgent than what you have been working on: Just deliberately click the FlowgencyTM logo to reorder the tasks by descending urgency as how it is at the time of the click. Tasks of which the associated time track is currently "off" will never raise in urgency while this is the case. In other words, these planned periods of still time are logically identical with the net second before. By default, paused tasks are even hidden from display.


Wherefore all that, what's the vision?
---------------------------------------

On the larger scale, if the software is used by many, this I hope is what FlowgencyTM will contribute to: As a kind of a feedback-driven pacemaker, there will be reliable rhythms of stress and relaxation in a global business life that is presently running amok, overheating more and more and could therefore collapse dramatically someday.

One could doubt, though, software is the right means of help, but in an era of quite religious belief in computers and technology in general (which is something computer pioneer and late technology critic Joseph Weizenbaum made me question), it is high time to teach our computers that we must be off regularly because we are at last who deliver them energy to run. To comply with them in their agnostic 24/7 dictate is idiotic, it is like having our children say what we are to do. Keep in mind, too: Your competitors never sleep, maybe since they suffer burn-out syndrome ;-).

I hope you get more flow experience – hence the name –, because you can focus better on tasks in your work as you can focus better on challenges in your life. 

The concept in detail
---------------------

This is the summary of the concept that you can read [in more detail](doc/konzept.en.md). Those who have got a good command of German might prefer [that version](doc/konzept.de.md) as it is at times more up-to-date than the english translation.

Installation
-------------

FlowgencyTM is a prototype, yet just a proof-of-concept that can work like a smooth or fail badly, for others as likely as for myself. So you are welcome to use FlowgencyTM with test data! Keep in mind that this software is alpha. This means that crashes and a regularly corrupted database are to be expected. So do not yet use it for vital projects or if you do really cannot help doing, backup often! Please file bug-reports, for which I thank you very much in advance.

FlowgencyTM is implemented in the Perl programming language, version 5.14+. Mac OS X and most linux distributions include it ready for use, ensure it is installed by running the command `perl -v`, or search the web how to install the latest version on your system. Windows users are recommended Strawberry Perl, please download from <http://strawberryperl.com/>.

Clone the git repository in a directory of your choice. With plain git on Linux enter at a shell prompt:

    $ git clone https://github.com/flowdy/FlowgencyTM.git
    $ cd FlowgencyTM/

For other systems, install the Git DVCS and do the according steps (cf. manual).

Check the dependencies
-----------------------

Check and install any prerequisites by running inside the FlowgencyTM directory, provided cpanm tool is installed on your system:

  cpanm --installdeps .


Bootstrap flow.db database file and run the program
----------------------------------------------------

FlowgencyTM does not yet work right from the box in a webbrowser. First, you need to bootstrap it with the development shell in the distribution, i.e. create a user and also a time model if you do not want to work 24/7 ;-):

    $ script/flow.sh -d flow.db
    Configuring sub-shell ...                                                            
    Now exec()'ing bash with the compiled rcfile instead of the default one ...          
    /bin/bash starting on behalf of FlowgencyTM::Shell ...                               
    # Welcome information and license note
    
    Initializing FlowTime::Shell ...Deploying new database in /tmp/FlowgencyTM/flow.db
    DONE.
    Press Enter to confirm new user floh OR change the name: floh
    Now ensuring the database contains a user entity ... User created. Don't forget to set up a time_model before you enter any tasks.
    [1]+ $FLOWGENCYTM_SHELL_PROCESS &
    
    # [Further information ...]
    
    FTM::~> timetracks default --week-pattern 'Mo-Th@9-16,Fr@7-14' -l 'Bureau'
       # [Note full hours: '-16' = effectively 16:59:59, '-14' eff. 14:59:59
       #  For *your* week pattern see doc/konzept.en.md for other examples]
    
    [1]+  Stopped              $FLOWGENCYTM_SHELL_PROCESS
    FTM::~> bye
    exit
    Cleaned up.

Second, run the command

    script/morbo

Please keep the terminal window open as it will output diagnostics if things go wrong. Then load the link it displays at the end in your webbrowser. If you have a local firewall installed, this might not work because of any rare and weird restrictions imposed. Refer to the manual of your firewall software how to make exceptions so that it does let you access your own system via HTTP (better contact your system administrator, if any).


Credits to other Open source projects used
------------------------------------------

FlowgencyTM could not even be thought of without the following Open source tools used. My acknowledgements to the respective developers:

  * Perl – The programing language used for the server-side
  * JQuery, JQueryUI – used for the client-side
  * Moose.pm – A Modern Object system for Perl
  * Date::Calc – Time-related calculations
  * SQLite, DBIx::Class – Database Model
  * Mojolicious – so you have your own server and need not expose any data, and
     you need not rely on the availability of a third party
  * Firefox – for testing and using FlowgencyTM (& various other browsers)
  * VIM – it's not an IDE, but what amazing power an editor can have!
  * git – distributed version control system

Contact Author / Project initiator
-----------------------------------

(Address split up for the sake of spam protection. Just glue it together and apply the "@" sign replacing "at".)

    fhess at mailbox. org


Copyleft and License
--------------------

Copyright (C) 2012, 2013, 2014 Florian Heß

FlowgencyTM is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowgencyTM is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowgencyTM. If not, see <http://www.gnu.org/licenses/>.

