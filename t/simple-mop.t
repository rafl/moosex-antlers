use strict;
use warnings;
use Test::More qw(no_plan);
use Class::MOP;
use MooseX::Antlers::Recorder;

my $ar = MooseX::Antlers::Recorder->new;

$ar->instrument_routines('Class::MOP::Class::add_attribute');
$ar->instrument_sub_constructors('Class::MOP::Method::Generated::_eval_closure');
$ar->instrument_method_installation;

sub setup_class {

  my $foo_class = Class::MOP::Class->initialize("Foo");

  $foo_class->add_attribute('one',
    name => 'one', reader => 'get_one',
    writer => { set_one => sub { $_[0]->{one} = $_[1] } },
  );

  $foo_class->make_immutable;

  $foo_class;

}

sub verify_class {

  ok(my $foo = Foo->new(one => 1), "created object");

  is($foo->get_one, 1, "got one");

  is($foo->set_one(2), 2, "got two");

  is($foo->get_one, 2, "still two");

}

my $foo_class = setup_class;

verify_class;

#warn join(', ', map { Foo->can($_) } qw(new get_one set_one));

use Data::Dumper;
$Data::Dumper::Deparse = 1;
$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;

#print Dumper($foo_class);

#print "\n---\n";

my $call = $ar->emit_call_results($foo_class);

undef($foo_class);

Class::MOP::remove_metaclass_by_name("Foo");

foreach my $name (qw(new get_one set_one)) {
  delete ${Foo::}{$name};
}

#warn $call;

#exit(0);

my ($save, $final) = eval $call;

#warn "here";

die $@ if $@;

{
  my $replay = sub { shift(@$save)->(@_) };

  no warnings 'redefine';

  local *Class::MOP::Class::add_attribute = $replay;

  local *Class::MOP::Class::make_immutable = sub {
    Class::MOP::store_metaclass_by_name('Foo', $_[0] = $final->());
  };

  $foo_class = setup_class;
}

verify_class;

#print Dumper($foo_class);
#warn join(', ', map { Foo->can($_) } qw(new get_one set_one));
