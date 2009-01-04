package Foo;

my $meta = Class::MOP::Class->initialize(__PACKAGE__);

$meta->add_attribute('one',
  name => 'one', reader => 'get_one',
  writer => { set_one => sub { $_[0]->{one} = $_[1] } },
);

$meta->make_immutable;

$::tests{do { __PACKAGE__ }} = sub {
  ::ok(my $foo = Foo->new(one => 1), "created object");
  
  ::is($foo->get_one, 1, "got one");
  
  ::is($foo->set_one(2), 2, "got two");
  
  ::is($foo->get_one, 2, "still two");
};

$meta;
