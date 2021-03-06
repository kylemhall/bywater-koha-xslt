#!/usr/bin/perl

# Copyright 2013 Oslo Public Library
#
# This file is part of Koha.
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

=head1 NAME

nl-search.pl - Script for searching the Norwegian national patron database

=head1 DESCRIPTION

This script will search the Norwegian national patron database, and let staff
import patrons from the natial database into the local database.

In order to use this, a username/password from the Norwegian national database
of libraries ("Base Bibliotek") is needed. A special key is also needed, in
order to decrypt and encrypt PIN-codes/passwords.

See http://www.lanekortet.no/ for more information (in Norwegian).

=cut

use Modern::Perl;
use CGI;
use C4::Auth;
use C4::Category;
use C4::Context;
use C4::Output;
use C4::Members;
use C4::Members::Attributes qw( SetBorrowerAttributes );
use Koha::NorwegianPatronDB qw( NLCheckSysprefs NLSearch NLDecodePin NLGetFirstname NLGetSurname NLSync );
use Koha::Database;
use Koha::DateUtils;

my $cgi = CGI->new;
my $dbh = C4::Context->dbh;
my $op  = $cgi->param('op');

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "members/nl-search.tt",
        query           => $cgi,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { borrowers => 1 },
        debug           => 1,
    }
);

my $userenv = C4::Context->userenv;

# Check sysprefs
my $check_result = NLCheckSysprefs();
if ( $check_result->{'error'} == 1 ) {
    $template->param( 'error' => $check_result );
    output_html_with_http_headers $cgi, $cookie, $template->output;
    exit 0;
}

if ( $op && $op eq 'search' ) {

    # Get the string we are searching for
    my $identifier = $cgi->param('q');
    if ( $identifier ) {
        # Local search
        my $local_results = Search( $identifier );
        $template->param( 'local_result' => $local_results );
        # Search NL, unless we got at least one hit and further searching is
        # disabled
        if ( scalar @{ $local_results } == 0 || C4::Context->preference("NorwegianPatronDBSearchNLAfterLocalHit") == 1 ) {
            # TODO Check the format of the identifier before searching NL
            my $result = NLSearch( $identifier );
            unless ($result->fault) {
                my $r = $result->result();
                # Send the data to the template
                my @categories = C4::Category->all;
                $template->param(
                    'result'     => $r,
                    'categories' => \@categories,
                );
            } else {
                $template->param( 'error' => join ', ', $result->faultcode, $result->faultstring, $result->faultdetail );
            }
        }
        $template->param( 'q' => $identifier );
    }

} elsif ( $op && $op eq 'save' ) {

    # This is where we map from fields in NL to fields in Koha
    my %borrower = (
        'surname'      => NLGetSurname( $cgi->param('navn') ),
        'firstname'    => NLGetFirstname( $cgi->param('navn') ),
        'sex'          => $cgi->param('kjonn'),
        'dateofbirth'  => $cgi->param('fdato'),
        'cardnumber'   => $cgi->param('lnr'),
        'userid'       => $cgi->param('lnr'),
        'address'      => $cgi->param('p_adresse1'),
        'address2'     => $cgi->param('p_adresse2'),
        'zipcode'      => $cgi->param('p_postnr'),
        'city'         => $cgi->param('p_sted'),
        'country'      => $cgi->param('p_land'),
        'B_address'    => $cgi->param('m_adresse1'),
        'B_address2'   => $cgi->param('m_adresse2'),
        'B_zipcode'    => $cgi->param('m_postnr'),
        'B_city'       => $cgi->param('m_sted'),
        'B_country'    => $cgi->param('m_land'),
        'password'     => NLDecodePin( $cgi->param('pin') ),
        'dateexpiry'   => $cgi->param('gyldig_til'),
        'email'        => $cgi->param('epost'),
        'mobile'       => $cgi->param('tlf_mobil'),
        'phone'        => $cgi->param('tlf_hjemme'),
        'phonepro'     => $cgi->param('tlf_jobb'),
        'branchcode'   => $userenv->{'branch'},
        'categorycode' => $cgi->param('categorycode'),
    );
    # Add the new patron
    my $borrowernumber = &AddMember(%borrower);
    if ( $borrowernumber ) {
        # Add extended patron attributes
        SetBorrowerAttributes($borrowernumber, [
            { code => 'fnr', value => $cgi->param('fnr_hash') },
        ] );
        # Override the default sync data created by AddMember
        my $borrowersync = Koha::Database->new->schema->resultset('BorrowerSync')->find({
            'synctype'       => 'norwegianpatrondb',
            'borrowernumber' => $borrowernumber,
        });
        $borrowersync->update({ 'syncstatus', 'synced' });
        $borrowersync->update({ 'lastsync',   $cgi->param('sist_endret') });
        $borrowersync->update({ 'hashed_pin', $cgi->param('pin') });
        # Try to sync in real time. If this fails it will be picked up by the cronjob
        NLSync({ 'borrowernumber' => $borrowernumber });
        # Redirect to the edit screen
        print $cgi->redirect( "/cgi-bin/koha/members/memberentry.pl?op=modify&destination=circ&borrowernumber=$borrowernumber" );
    } else {
        $template->param( 'error' => 'COULD_NOT_ADD_PATRON' );
    }
}

output_html_with_http_headers $cgi, $cookie, $template->output;

=head1 AUTHOR

Magnus Enger <digitalutvikling@gmail.com>

=cut
