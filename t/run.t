 #!/usr/bin/env perl

use strict;
use warnings;

use lib "t/tests";
use Test::Class;
use Test::App::FatPacker::Script;
use Test::App::FatPacker::Script::Parsing;

Test::Class->runtests;