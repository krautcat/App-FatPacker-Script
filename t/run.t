 #!/usr/bin/env perl

use strict;
use warnings;

use lib "t/tests";
use Test::Class;
use Test::App::FatPacker::Script;
use Test::App::FatPacker::Script::Parsing;
use Test::App::FatPacker::Script::Core;

Test::Class->runtests;