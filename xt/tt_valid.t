#!/usr/bin/perl

# This file is part of Koha.
#
# Copyright (C) 2011 Tamil s.a.r.l.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use warnings;
use strict;
use Test::More tests => 2;
use File::Find;
use Cwd;
use C4::TTParser;

my @themes;

# OPAC themes
my $opac_dir  = 'koha-tmpl/opac-tmpl';
opendir ( my $dh, $opac_dir ) or die "can't opendir $opac_dir: $!";
for my $theme ( grep { not /^\.|lib|js/ } readdir($dh) ) {
    push @themes, "$opac_dir/$theme/en";
}
close $dh;

# STAFF themes
my $staff_dir = 'koha-tmpl/intranet-tmpl';
opendir ( $dh, $staff_dir ) or die "can't opendir $staff_dir: $!";
for my $theme ( grep { not /^\.|lib|js/ } readdir($dh) ) {
    push @themes, "$staff_dir/$theme/en";
}
close $dh;

my @files_with_directive_in_tag = do {
    my @files;
    find( sub {
        my $dir = getcwd();
        return if $dir =~ /blib/;
        return unless /\.(tt|inc)$/;
        my $name = $_;
        my $parser = C4::TTParser->new;
        $parser->build_tokens( $name );  
        my @lines;
        while ( my $token = $parser->next_token ) {
            my $attr = $token->{_attr};
            next unless $attr;
            push @lines, $token->{_lc} if $attr->{'[%'} or $attr->{'[%-'};
        }
        ($dir) = $dir =~ /koha-tmpl\/(.*)$/;
        push @files, { name => "$dir/$name", lines => \@lines } if @lines;
      }, @themes
    );
    @files;
};


ok( !@files_with_directive_in_tag, "TT syntax: not using TT directive within HTML tag" )
    or diag(
          "Files list: \n",
          join( "\n", map { $_->{name} . ': ' . join(', ', @{$_->{lines}})
              } @files_with_directive_in_tag )
       );

my $testtoken = 0;
my $ttparser = C4::TTParser->new();
$ttparser->unshift_token($testtoken);
my $testtokenagain = C4::TTParser::next_token();
is( $testtoken, $testtokenagain, "Token received same as original put on stack");


=head1 NAME

tt_valid.t

=head1 DESCRIPTION

This test validate Template Toolkit (TT) Koha files.

For the time being an unique validation is done: Test if TT files contain TT
directive within HTML tag. For example:

  <li[% IF

This kind of constuction MUST be avoided because it break Koha translation
process.

=head1 USAGE

From Koha root directory:

prove -v xt/tt_valid.t

=cut

