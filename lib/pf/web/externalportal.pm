package pf::web::externalportal;

=head1 NAME

pf::web::externalportal - handle the detection of an external portal workflow

=cut

=head1 DESCRIPTION

pf::web::externalportal detect external portal workflow

=cut

use strict;
use warnings;

use Apache2::Const -compile => qw(:http);
use Apache2::Request;
use Apache2::RequestRec;
use Log::Log4perl;

use pf::config;
use pf::iplog qw(iplog_update);
use pf::locationlog qw(locationlog_view_open_mac);
use pf::Portal::Session;
use pf::util;
use pf::web::constants;
use pf::web::util;

=head1 SUBROUTINES

=over

=item new

Constructor

=cut
sub new {
    my ( $class, %arg ) = @_;
    my $logger = Log::Log4perl::get_logger(__PACKAGE__);

    $logger->trace("Instanciating a new " . __PACKAGE__ . " object");

    my $this = bless {
        'is_external_portal'    => undef,
        'type'                  => undef,
    }, $class;

    foreach my $value ( keys %arg ) {
        $this->{'_' . $value} = $arg{$value};
    }

    return $this;
}

=item _setIsExternalPortal

PRIVATE METHOD: Should be call only from within this class.

Set _is_exernal_portal object attribute

Value ($value) can be either true or false.

We are not sanitizing the input of $value. Since this method is a private one, we trust the caller (another 
method from within the class) to sanitize it.

=cut
sub _setIsExternalPortal {
    my ( $this, $value ) = @_;
    my $logger = Log::Log4perl::get_logger(__PACKAGE__);

    $logger->debug("Setting object attribute _is_external_portal to $value");

    $this->{_is_external_portal} = $value;
}

=item _setType

PRIVATE METHOD: Should be call only from within this class.

Set _type object attribute

Value ($value) is the type of the external captive portal (Cisco, Ruckus, ...)

We are not sanitizing the input of $value. Since this method is a private one, we trust the caller (another 
method from within the class) to sanitize it.

=cut
sub _setType {
    my ( $this, $value ) = @_;
    my $logger = Log::Log4perl::get_logger(__PACKAGE__);

    $logger->debug("Setting object attribute _type to $value");

    $this->{_type} = $value;
}

=item isExternalPortal

Return true or false (the value of the _is_external_portal object attribute).

=cut
sub isExternalPortal {
    my ( $this ) = @_;
    my $logger = Log::Log4perl::get_logger(__PACKAGE__);

    my $value = $this->{_is_external_portal};
    $logger->debug("Returning value $value");

    return $value;
}

=item getType

Return the type of the external captive portal (Cisco, Ruckus, ...)

=cut
sub getType {
    my ( $this ) = @_;
    my $logger = Log::Log4perl::get_logger(__PACKAGE__);

    my $value = $this->{_type};
    $logger->debug("Returning value $value");

    return $value;
}

=item detect

Detect if we're dealing with an external captive portal or not and set object attributes accordingly.

=cut
sub detect {
    my ( $this ) = @_;
}


=item external_captive_portal

Instantiate the switch module and use a specific captive portal

=cut

sub external_captive_portal {
    my ($self, $switchId, $req, $r, $session) = @_;
    my $logger = Log::Log4perl->get_logger(__PACKAGE__);

    my $switch;
    if (defined($switchId)) {
        if (pf::SwitchFactory::hasId($switchId)) {
            $switch =  pf::SwitchFactory->getInstance()->instantiate($switchId);
        } else {
            my $locationlog_entry = locationlog_view_open_mac($switchId);
            $switch = pf::SwitchFactory->getInstance()->instantiate($locationlog_entry->{'switch'});
        }

        if (defined($switch) && $switch ne '0' && $switch->supportsExternalPortal) {
            my ($client_mac,$client_ssid,$client_ip,$redirect_url,$grant_url,$status_code) = $switch->parseUrl(\$req);
            my %info = (
                'client_mac' => $client_mac,
            );
            my $portalSession = pf::Portal::Session->new(%info);
            $portalSession->setClientIp($client_ip) if (defined($client_ip));
            $portalSession->setDestinationUrl($redirect_url) if (defined($redirect_url));
            $portalSession->setGrantUrl($grant_url) if (defined($grant_url));
            iplog_update($client_mac,$client_ip,100) if (defined ($client_ip) && defined ($client_mac));
            return $portalSession->session->id();
        } else {
            return 0;
        }
    }
    elsif (defined($session)) {
        my (%session_id);
        pf::web::util::session(\%session_id,$session);
        if ($session_id{_session_id} eq $session) {
            my $switch = $session_id{switch};
            my $portalSession = pf::Portal::Session->new(%session_id);
            $portalSession->setClientMac($session_id{client_mac}) if (defined($session_id{client_mac}));
            $portalSession->setDestinationUrl($r->headers_in->{'Referer'}) if (defined($r->headers_in->{'Referer'}));
            return $portalSession->session->id();
        } else {
            return 0;
        }
    }
    else {
        return 0;
    }
}

=item handle

handle the detection of the external portal

=cut

sub handle {
    my ($self,$r) = @_;
    my $req = Apache2::Request->new($r);
    my $is_external_portal;
    foreach my $param ($req->param) {
        if ($param =~ /$WEB::EXTERNAL_PORTAL_PARAM/o) {
            my $value;
            $value = clean_mac($req->param($param)) if valid_mac($req->param($param));
            $value = $req->param($param) if  valid_ip($req->param($param));
            if (defined($value)) {
                my $cgi_session_id = $self->external_captive_portal($value,$req,$r,undef);
                if ($cgi_session_id ne '0') {
                    return $cgi_session_id;
                }
            }
        }
    }

    # Try to fetch the parameters in the session
    if ($r->uri =~ /$WEB::EXTERNAL_PORTAL_PARAM/o) {
        my $cgi_session_id = $self->external_captive_portal(undef,undef,$r,$1);
            if ($cgi_session_id ne '0') {
                return $cgi_session_id;
            }
    }
    return 0;
}

=back

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2014 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

1;
