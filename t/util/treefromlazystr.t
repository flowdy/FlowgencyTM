use strict;
use Test::More;
use FTM::User;

my ($p) = FTM::User::Common::TaskManager->get_tfls_parser( -dry => 1 );

is_deeply [ $p->parse('Dies ist einer ;0 Und das ein weiterer') ], [ { title => 'Dies ist einer' }, { title => 'Und das ein weiterer' } ], 'Two simple tasks (titles only)';

is_deeply $p->parse('Dies ist ein Task ;1 mit einem untergeordneten Step =step'), { title => 'Dies ist ein Task', substeps => ';step', steps => { step => { description => 'mit einem untergeordneten Step' } } }, 'Task mit untergeordnetem Step, Inline-Trenner';

is_deeply $p->parse("Man kann auch Newline benutzen: Dies ist ein Task\n1 mit einem untergeordneten Step =step"), { title => 'Man kann auch Newline benutzen: Dies ist ein Task', substeps => ';step', steps => { step => { description => 'mit einem untergeordneten Step' } } }, '... Trennung per Newline';

is_deeply $p->parse("Man kann auch Newline benutzen: Dies ist ein Task\n1mit einem untergeordneten Step =step"), { title => 'Man kann auch Newline benutzen: Dies ist ein Task', substeps => ';step', steps => { step => { description => 'mit einem untergeordneten Step' } } }, '... per Newline ohne Leerraum nach der Ziffer';

is_deeply $p->parse("Dies ist ein Task mit Deadline ;until 30.11.\n1und einem untergeordneten Step =step"), { title => 'Dies ist ein Task mit Deadline', timestages => [{ track => 'default', until_date => '30.11.' }], substeps => ';step', steps => { step => { description => 'und einem untergeordneten Step' } } }, 'Task mit Attributblatt und untergeordnetem Step';

chomp(my $long_str = <<'EOS');
This is a task with a deadline ;until 30.11.
1and a subordinated step =one ;2 The whole thing is nestable in that\
many levels you want, however, in a certain depth you'll find it not\
manageable any more =two ;1 We decrement in order to return to a higher level =three
;from 15.11. ;until 20.11.@bureau; 24.11.@labor
EOS

is_deeply $p->parse($long_str), {'substeps' => ';one|three', steps => { one => { 'substeps' => ';two', description => 'and a subordinated step' }, two => {description => 'The whole thing is nestable in that many levels you want, however, in a certain depth you\'ll find it not manageable any more'}, three => { description => 'We decrement in order to return to a higher level', from_date => '15.11.', timestages => [{ track => 'bureau', until_date => '20.11.'}, { track => 'labor', until_date => '24.11.'}] } }, timestages => [{ track => 'default', until_date => '30.11.' }], title => 'This is a task with a deadline'}, "two levels, timestages in a step";

chomp($long_str = <<'EOS');
  This is the task title ;description you can apply metadata to it, just append space and semicolon and after it, without space, the metadata field identifier ;from 9-14 ;until 30 10:00@office; 10-10 17:00@labor ;1 This is a substep =foo of the step before, since you incremented the level indicator from 0 to 1 ;1This is another substep on the same level, labeled =bar, it is no problem when you omit the space after the level indicator
   ;2 this is a subsubstep =bing, again do not forget to increment the number of the separator. You can use newline instead of plain whitespace before the semicolon, you can even mix both for indentation, if you want.\nBut escape any literal newline.\

  Literal space of any kind is escaped with *one* backslash (\\).
   ;3 the nesting level =three ;4 can be =four ;5 arbitrarily deep, =five ;6: =but don't exaggarate, think well about how many levels match your task. ;1 Mind the =general motto: As simple as possible, as complex as necessary and KISS - keep it simple and stupid.
EOS

my $href = $p->parse($long_str);

$DB::single=1;
done_testing;

__END__

Weitere Tests hinzuzufügen:

#  $p = get_flowtime_task_parser()

#  x $p->parse("Hallo Welt!")                                                                             
0  HASH(0x3076aa8)
   'title' => 'Hallo Welt!'
#  x $p->parse("Hallo Welt! ;dies ist ein Attribut")
0  HASH(0x3184c90)
   'dies' => 'ist ein Attribut'
   'title' => 'Hallo Welt!'
#  x $p->parse("Hallo Welt!;dies ist ein Attribut")
0  HASH(0x32ac5b8)
   'title' => 'Hallo Welt!;dies ist ein Attribut'
#  x $p->parse("Hallo Welt! ;dies ist ein Attribut")
0  HASH(0x31845d0)
   'dies' => 'ist ein Attribut'
   'title' => 'Hallo Welt!'
#  x $p->parse("Hallo Welt! ;dies ist ein Attribut ;0 Hallo Mars, du auch hier?")
0  HASH(0x3255730)
   'dies' => 'ist ein Attribut'
   'title' => 'Hallo Welt!'
1  HASH(0x3255778)
   'title' => 'Hallo Mars, du auch hier?'
#  x $p->parse('Hallo Welt! ;dies ist ein Attribut ;0 Hallo Mars, du auch \;hier?')
0  HASH(0x3255760)
   'dies' => 'ist ein Attribut'
   'title' => 'Hallo Welt!'
1  HASH(0x319e480)
   'title' => 'Hallo Mars, du auch ;hier?'
#  x $p->parse('Hallo Welt! ;dies ist ein Attribut ;0 Hallo Mars, du auch ;hier, das ist ja Wahnsinn!')
Missing key in line "hier, das ist ja Wahnsinn!" at TreeFromLazyStr.pm line 220
#  x $p->parse('Hallo Welt! ;dies ist ein Attribut ;0 Hallo Mars, du auch ;hier , das ist ja Wahnsinn!')
0  HASH(0x323a720)
   'dies' => 'ist ein Attribut'
   'title' => 'Hallo Welt!'
1  HASH(0x3255c58)
   'hier' => ', das ist ja Wahnsinn!'
   'title' => 'Hallo Mars, du auch'
#  x $p->parse('Hallo Welt! \;dies ist ein Attribut ;0 Hallo Mars, du auch ;hier , das ist ja Wahnsinn!') 
0  HASH(0x319e7c8)
   'title' => 'Hallo Welt! ;dies ist ein Attribut'
1  HASH(0x3256b30)
   'hier' => ', das ist ja Wahnsinn!'
   'title' => 'Hallo Mars, du auch'
#  x $p->parse('Hallo Welt! \;dies ist ein Attr\033ibut ;0 Hallo Mars, du auch ;hier , das ist ja Wahnsinn!')
0  HASH(0x3184c90)
   'title' => "Hallo Welt! ;dies ist ein Attr\eibut"
1  HASH(0x3255718)
   'hier' => ', das ist ja Wahnsinn!'
   'title' => 'Hallo Mars, du auch'
#  x $p->parse('Ich escape einen Trenner\ ;1und habe Spaß daran')
0  HASH(0x2a5e7b8)
   'title' => 'Ich escape einen Trenner ;1und habe Spaß daran'
#  x $p->parse('Ich escape einen Trenner \;1und habe Spaß daran')
0  HASH(0x2b6cf40)
   'title' => 'Ich escape einen Trenner ;1und habe Spaß daran'
#  x $p->parse('Ich escape einen Trenner ;1und habe Spaß daran')
0  HASH(0x2c703b0)
   'substeps' => ARRAY(0x2b73268)
      0  HASH(0x2c3d880)
         'title' => 'und habe Spaß daran'
   'title' => 'Ich escape einen Trenner'
#  x $p->parse('Ich escape einen Trenner\  ;1und habe Spaß daran')
0  HASH(0x2e43688)
   'substeps' => ARRAY(0x2f58098)
      0  HASH(0x2f51f20)
         'title' => 'und habe Spaß daran'
   'title' => 'Ich escape einen Trenner '
#  x $p->parse('Ich escape einen Trenner\ \ ;1und habe Spaß daran')
0  HASH(0x2f511b8)
   'title' => 'Ich escape einen Trenner  ;1und habe Spaß daran'
#  $p = get_flowtime_task_parser(inline_sep_mark => '][')

#  p $p->inline_sep_mark
(?^:(?<!\\)\]\[)
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][, das geht genauso gut')  
0  HASH(0x37ba6e8)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x38c9c58)
   'title' => 'ich die Bestandteile hier mit ][, das geht genauso gut'
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit][das geht genauso gut')  
0  HASH(0x38c9718)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x397dcf0)
   'das' => 'geht genauso gut'
   'title' => 'ich die Bestandteile hier mit'
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit\][ ][das geht genauso gut')  
0  HASH(0x39973e0)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x38e18e0)
   'das' => 'geht genauso gut'
   'title' => 'ich die Bestandteile hier mit][ '
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit\][][das geht genauso gut')  
0  HASH(0x38c97f0)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x3997a28)
   'das' => 'geht genauso gut'
   'title' => 'ich die Bestandteile hier mit]['
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][][das geht genauso gut')  
0  HASH(0x38c96d0)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x3997a10)
   'das' => 'geht genauso gut'
   'title' => 'ich die Bestandteile hier mit ]['
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][][das geht genauso gut][2Selbst ein Fehler wird artig geworfen, wenn ich mich verzähle')  
Unexpected separator in a leaf: 2 - possibly miscounted? at TreeFromLazyStr.pm line 184
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][][das geht genauso gut][1Hier noch mal mit untergeordnetem Zeug')  
0  HASH(0x3997b30)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x39979c8)
   'das' => 'geht genauso gut'
   'substeps' => ARRAY(0x38ce4a8)
      0  HASH(0x38cdf68)
         'parents_name' => '(anonymous parent)'
         'title' => 'Hier noch mal mit untergeordnetem Zeug'
   'title' => 'ich die Bestandteile hier mit ]['
#  x $p->parse('Wie Sie sehen, trenne][0 ich die =Mama Bestandteile hier mit \][][das geht genauso gut][1Hier noch mal mit untergeordnetem Zeug')  
0  HASH(0x3998158)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x39980c8)
   'das' => 'geht genauso gut'
   'name' => 'Mama'
   'substeps' => ARRAY(0x3998110)
      0  HASH(0x3997968)
         'parents_name' => 'Mama'
         'title' => 'Hier noch mal mit untergeordnetem Zeug'
   'title' => 'ich die Bestandteile hier mit ]['
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][][das geht genauso gut ][name Mama][1Hier noch mal mit untergeordnetem Zeug')  
0  HASH(0x3998f20)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x3a06758)
   'das' => 'geht genauso gut '
   'name' => 'Mama'
   'substeps' => ARRAY(0x3998e78)
      0  HASH(0x39973f8)
         'parents_name' => 'Mama'
         'title' => 'Hier noch mal mit untergeordnetem Zeug'
   'title' => 'ich die Bestandteile hier mit ]['
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][][das geht genauso gut][1Hier noch mal mit untergeordnetem Zeug')  
0  HASH(0x3997938)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x3a06698)
   'das' => 'geht genauso gut'
   'substeps' => ARRAY(0x3a06728)
      0  HASH(0x3998ea8)
         'parents_name' => '(anonymous parent)'
         'title' => 'Hier noch mal mit untergeordnetem Zeug'
   'title' => 'ich die Bestandteile hier mit ]['
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][][das geht genauso gut ][name Mama][1Hier noch mal mit untergeordnetem Zeug')  
0  HASH(0x388fc58)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x37ba6e8)
   'das' => 'geht genauso gut '
   'name' => 'Mama'
   'substeps' => ARRAY(0x3998f68)
      0  HASH(0x3997440)
         'parents_name' => 'Mama'
         'title' => 'Hier noch mal mit untergeordnetem Zeug'
   'title' => 'ich die Bestandteile hier mit ]['
