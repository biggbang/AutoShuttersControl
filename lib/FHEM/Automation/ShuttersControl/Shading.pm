###############################################################################
#
# Developed with Kate
#
#  (c) 2018-2020 Copyright: Marko Oldenburg (fhemsupport@cooltux.net)
#  All rights reserved
#
#   Special thanks goes to:
#       - Bernd (Cluni) this module is based on the logic of his script "Rollladensteuerung für HM/ROLLO inkl. Abschattung und Komfortfunktionen in Perl" (https://forum.fhem.de/index.php/topic,73964.0.html)
#       - Beta-User for many tests, many suggestions and good discussions
#       - pc1246 write english commandref
#       - FunkOdyssey commandref style
#       - sledge fix many typo in commandref
#       - many User that use with modul and report bugs
#       - Christoph (christoph.kaiser.in) Patch that expand RegEx for Window Events
#       - Julian (Loredo) expand Residents Events for new Residents functions
#       - Christoph (Christoph Morrison) for fix Commandref, many suggestions and good discussions
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License,or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################

## unserer packagename
package FHEM::Automation::ShuttersControl::Shading;

use strict;
use warnings;
use POSIX qw(strftime);
use utf8;

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          Log3
          gettimeofday
          readingsBeginUpdate
          readingsBulkUpdate
          readingsEndUpdate
        )
    );
}


sub ShadingProcessing {
### angleMinus ist $FHEM::Automation::ShuttersControl::shutters->getShadingAzimuthLeft
### anglePlus ist $FHEM::Automation::ShuttersControl::shutters->getShadingAzimuthRight
### winPos ist die Fensterposition $FHEM::Automation::ShuttersControl::shutters->getDirection
    my ( $hash, $shuttersDev, $azimuth, $elevation, $outTemp,
        $azimuthLeft, $azimuthRight )
      = @_;

    my $name = $hash->{NAME};
    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($shuttersDev);
    my $brightness = $FHEM::Automation::ShuttersControl::shutters->getBrightnessAverage;

    \&FHEM::Automation::ShuttersControl::ASC_Debug(
            'ShadingProcessing: '
          . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
          . ' - Übergebende Werte - Azimuth:'
          . $azimuth
          . ', Elevation: '
          . $elevation
          . ', Brightness: '
          . $brightness
          . ', OutTemp: '
          . $outTemp
          . ', Azimut Beschattung: '
          . $azimuthLeft
          . ', Azimut Endschattung: '
          . $azimuthRight
          . ', Ist es nach der Zeitblockadezeit: '
          . ( IsAfterShuttersTimeBlocking($shuttersDev) ? 'JA' : 'NEIN' )
          . ', Das Rollo ist in der Beschattung und wurde manuell gefahren: '
          . ( $FHEM::Automation::ShuttersControl::shutters->getShadingManualDriveStatus ? 'JA' : 'NEIN' )
          . ', Ist es nach der Hälfte der Beschattungswartezeit: '
          . (
            ( int( gettimeofday() ) - $FHEM::Automation::ShuttersControl::shutters->getShadingStatusTimestamp ) <
              ( $FHEM::Automation::ShuttersControl::shutters->getShadingWaitingPeriod / 2 ) ? 'NEIN' : 'JA'
          )
    );

    Log3( $name, 4,
            "AutoShuttersControl ($name) - Shading Processing, Rollladen: "
          . $shuttersDev
          . " Azimuth: "
          . $azimuth
          . " Elevation: "
          . $elevation
          . " Brightness: "
          . $brightness
          . " OutTemp: "
          . $outTemp );

    return
      if ( $azimuth == -1
        || $elevation == -1
        || $brightness == -1
        || $outTemp == -100
        || ( int( gettimeofday() ) - $FHEM::Automation::ShuttersControl::shutters->getShadingStatusTimestamp ) <
        ( $FHEM::Automation::ShuttersControl::shutters->getShadingWaitingPeriod / 2 )
        || $FHEM::Automation::ShuttersControl::shutters->getShadingMode eq 'off' );

    Log3( $name, 4,
            "AutoShuttersControl ($name) - Shading Processing, Rollladen: "
          . $shuttersDev
          . " Nach dem return" );

    my $getShadingPos    = $FHEM::Automation::ShuttersControl::shutters->getShadingPos;
    my $getStatus        = $FHEM::Automation::ShuttersControl::shutters->getStatus;
    my $oldShadingStatus = $FHEM::Automation::ShuttersControl::shutters->getShadingStatus;
    my $shuttersDevHash  = $defs{$shuttersDev};

    my $getModeUp = $FHEM::Automation::ShuttersControl::shutters->getModeUp;
    my $homemode  = $FHEM::Automation::ShuttersControl::shutters->getHomemode;

    \&FHEM::Automation::ShuttersControl::ASC_Debug( 'ShadingProcessing: '
          . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
          . ' - Alle Werte für die weitere Verarbeitung sind korrekt vorhanden und es wird nun mit der Beschattungsverarbeitung begonnen'
    );

    if (
        (
               $outTemp < $FHEM::Automation::ShuttersControl::shutters->getShadingMinOutsideTemperature - 4
            || $azimuth < $azimuthLeft
            || $azimuth > $azimuthRight
            || !$FHEM::Automation::ShuttersControl::shutters->getIsDay
        )
        && $FHEM::Automation::ShuttersControl::shutters->getShadingStatus ne 'out'
      )
    {
        #         $FHEM::Automation::ShuttersControl::shutters->setShadingLastStatus('in');
        $FHEM::Automation::ShuttersControl::shutters->setShadingStatus('out');

        \&FHEM::Automation::ShuttersControl::ASC_Debug( 'ShadingProcessing: '
              . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
              . ' - Es ist Nacht oder die Aussentemperatur unterhalb der Shading Temperatur. Die Beschattung wird Zwangsbeendet'
        );

        Log3( $name, 4,
"AutoShuttersControl ($name) - Shading Processing - Der Sonnenstand ist ausserhalb der Winkelangaben oder die Aussentemperatur unterhalb der Shading Temperatur "
        );
    }
    elsif ($azimuth < $azimuthLeft
        || $azimuth > $azimuthRight
        || $elevation < $FHEM::Automation::ShuttersControl::shutters->getShadingMinElevation
        || $elevation > $FHEM::Automation::ShuttersControl::shutters->getShadingMaxElevation
        || $brightness < $FHEM::Automation::ShuttersControl::shutters->getShadingStateChangeCloudy
        || $outTemp < $FHEM::Automation::ShuttersControl::shutters->getShadingMinOutsideTemperature - 1 )
    {
        $FHEM::Automation::ShuttersControl::shutters->setShadingStatus('out reserved')
          if ( $FHEM::Automation::ShuttersControl::shutters->getShadingStatus eq 'in'
            || $FHEM::Automation::ShuttersControl::shutters->getShadingStatus eq 'in reserved' );

        if (
            (
                $FHEM::Automation::ShuttersControl::shutters->getShadingStatus eq 'out reserved'
                and
                ( int( gettimeofday() ) - $FHEM::Automation::ShuttersControl::shutters->getShadingStatusTimestamp )
            ) > $FHEM::Automation::ShuttersControl::shutters->getShadingWaitingPeriod
          )
        {
            $FHEM::Automation::ShuttersControl::shutters->setShadingStatus('out');

            #             $FHEM::Automation::ShuttersControl::shutters->setShadingLastStatus('in')
            #               if ( $FHEM::Automation::ShuttersControl::shutters->getShadingLastStatus eq 'out' );
        }

        Log3( $name, 4,
                "AutoShuttersControl ($name) - Shading Processing, Rollladen: "
              . $shuttersDev
              . " In der Out Abfrage, Shadingwert: "
              . $FHEM::Automation::ShuttersControl::shutters->getShadingStatus
              . ", Zeitstempel: "
              . $FHEM::Automation::ShuttersControl::shutters->getShadingStatusTimestamp );

        \&FHEM::Automation::ShuttersControl::ASC_Debug( 'ShadingProcessing: '
              . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
              . ' - Einer der Beschattungsbedingungen wird nicht mehr erfüllt und somit wird der Beschattungsstatus um eine Stufe reduziert. Alter Status: '
              . $oldShadingStatus
              . ' Neuer Status: '
              . $FHEM::Automation::ShuttersControl::shutters->getShadingStatus );
    }
    elsif ($azimuth > $azimuthLeft
        && $azimuth < $azimuthRight
        && $elevation > $FHEM::Automation::ShuttersControl::shutters->getShadingMinElevation
        && $elevation < $FHEM::Automation::ShuttersControl::shutters->getShadingMaxElevation
        && $brightness > $FHEM::Automation::ShuttersControl::shutters->getShadingStateChangeSunny
        && $outTemp > $FHEM::Automation::ShuttersControl::shutters->getShadingMinOutsideTemperature )
    {
        if (   $FHEM::Automation::ShuttersControl::shutters->getShadingStatus eq 'out'
            || $FHEM::Automation::ShuttersControl::shutters->getShadingStatus eq 'out reserved' )
        {
            $FHEM::Automation::ShuttersControl::shutters->setShadingStatus('in reserved');

        }

        if ( $FHEM::Automation::ShuttersControl::shutters->getShadingStatus eq 'in reserved'
            and
            ( int( gettimeofday() ) - $FHEM::Automation::ShuttersControl::shutters->getShadingStatusTimestamp ) >
            ( $FHEM::Automation::ShuttersControl::shutters->getShadingWaitingPeriod / 2 ) )
        {
            $FHEM::Automation::ShuttersControl::shutters->setShadingStatus('in');

            #             $FHEM::Automation::ShuttersControl::shutters->setShadingLastStatus('out')
            #               if ( $FHEM::Automation::ShuttersControl::shutters->getShadingLastStatus eq 'in' );
        }

        Log3( $name, 4,
                "AutoShuttersControl ($name) - Shading Processing, Rollladen: "
              . $shuttersDev
              . " In der In Abfrage, Shadingwert: "
              . $FHEM::Automation::ShuttersControl::shutters->getShadingStatus
              . ", Zeitstempel: "
              . $FHEM::Automation::ShuttersControl::shutters->getShadingStatusTimestamp );

        \&FHEM::Automation::ShuttersControl::ASC_Debug( 'ShadingProcessing: '
              . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
              . ' - Alle Beschattungsbedingungen wurden erfüllt und somit wird der Beschattungsstatus um eine Stufe angehoben. Alter Status: '
              . $oldShadingStatus
              . ' Neuer Status: '
              . $FHEM::Automation::ShuttersControl::shutters->getShadingStatus );
    }

    ShadingProcessingDriveCommand( $hash, $shuttersDev )
      if (
           \&FHEM::Automation::ShuttersControl::IsAfterShuttersTimeBlocking($shuttersDev)
        && !$FHEM::Automation::ShuttersControl::shutters->getShadingManualDriveStatus
        && $FHEM::Automation::ShuttersControl::shutters->getRoommatesStatus ne 'gotosleep'
        && $FHEM::Automation::ShuttersControl::shutters->getRoommatesStatus ne 'asleep'
        && (
            (
                   $FHEM::Automation::ShuttersControl::shutters->getShadingStatus eq 'out'
                && $FHEM::Automation::ShuttersControl::shutters->getShadingLastStatus eq 'in'
            )
            || (   $FHEM::Automation::ShuttersControl::shutters->getShadingStatus eq 'in'
                && $FHEM::Automation::ShuttersControl::shutters->getShadingLastStatus eq 'out' )
        )
        && (   $FHEM::Automation::ShuttersControl::shutters->getShadingMode eq 'always'
            || $FHEM::Automation::ShuttersControl::shutters->getShadingMode eq $homemode )
        && (
               $FHEM::Automation::ShuttersControl::shutters->getModeUp eq 'always'
            || $FHEM::Automation::ShuttersControl::shutters->getModeUp eq $homemode
            || $FHEM::Automation::ShuttersControl::shutters->getModeUp eq 'off'
            || $FHEM::Automation::ShuttersControl::shutters->getModeUp eq 'absent'
            || (   $FHEM::Automation::ShuttersControl::shutters->getModeUp eq 'home'
                && $homemode ne 'asleep' )
        )
        && (
            (
                (
                    int( gettimeofday() ) -
                    $FHEM::Automation::ShuttersControl::shutters->getShadingStatusTimestamp
                ) < 2
                && $FHEM::Automation::ShuttersControl::shutters->getStatus != $FHEM::Automation::ShuttersControl::shutters->getClosedPos
            )
            || (  !$FHEM::Automation::ShuttersControl::shutters->getQueryShuttersPos( $FHEM::Automation::ShuttersControl::shutters->getShadingPos )
                && $FHEM::Automation::ShuttersControl::shutters->getIfInShading )
            || (  !$FHEM::Automation::ShuttersControl::shutters->getIfInShading
                && $FHEM::Automation::ShuttersControl::shutters->getStatus == $FHEM::Automation::ShuttersControl::shutters->getShadingPos )
        )
      );

    readingsBeginUpdate($shuttersDevHash);
    readingsBulkUpdate(
        $shuttersDevHash,
        'ASC_ShadingMessage',
        'INFO: current shading status is \''
          . $FHEM::Automation::ShuttersControl::shutters->getShadingStatus . '\''
          . ' - next check in '
          . (
            (
                (
                         $FHEM::Automation::ShuttersControl::shutters->getShadingLastStatus eq 'out reserved'
                      || $FHEM::Automation::ShuttersControl::shutters->getShadingLastStatus eq 'out'
                )
                ? $FHEM::Automation::ShuttersControl::shutters->getShadingWaitingPeriod
                : $FHEM::Automation::ShuttersControl::shutters->getShadingWaitingPeriod / 2
            )
          ) / 60
          . 'm'
    );
    readingsEndUpdate( $shuttersDevHash, 1 );

    return;
}

sub ShadingProcessingDriveCommand {
    my $hash        = shift;
    my $shuttersDev = shift;

    my $name = $hash->{NAME};
    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($shuttersDev);

    my $getShadingPos = $FHEM::Automation::ShuttersControl::shutters->getShadingPos;
    my $getStatus     = $FHEM::Automation::ShuttersControl::shutters->getStatus;

    $FHEM::Automation::ShuttersControl::shutters->setShadingStatus( $FHEM::Automation::ShuttersControl::shutters->getShadingStatus );

    if (
           $FHEM::Automation::ShuttersControl::shutters->getShadingStatus eq 'in'
        && $getShadingPos != $getStatus
        && ( \&FHEM::Automation::ShuttersControl::CheckIfShuttersWindowRecOpen($shuttersDev) != 2
            || $FHEM::Automation::ShuttersControl::shutters->getShuttersPlace ne 'terrace' )
      )
    {
        $FHEM::Automation::ShuttersControl::shutters->setLastDrive('shading in');
        ShuttersCommandSet( $hash, $shuttersDev, $getShadingPos );

        \&FHEM::Automation::ShuttersControl::ASC_Debug( 'ShadingProcessingDriveCommand: '
              . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
              . ' - Der aktuelle Beschattungsstatus ist: '
              . $FHEM::Automation::ShuttersControl::shutters->getShadingStatus
              . ' und somit wird nun in die Position: '
              . $getShadingPos
              . ' zum Beschatten gefahren' );
    }
    elsif ($FHEM::Automation::ShuttersControl::shutters->getShadingStatus eq 'out'
        && $getShadingPos == $getStatus )
    {
        $FHEM::Automation::ShuttersControl::shutters->setLastDrive('shading out');

        \&FHEM::Automation::ShuttersControl::ShuttersCommandSet(
            $hash,
            $shuttersDev,
            (
                  $getShadingPos == $FHEM::Automation::ShuttersControl::shutters->getLastPos
                ? $FHEM::Automation::ShuttersControl::shutters->getOpenPos
                : (
                    $FHEM::Automation::ShuttersControl::shutters->getQueryShuttersPos( $FHEM::Automation::ShuttersControl::shutters->getLastPos )
                    ? (
                          $FHEM::Automation::ShuttersControl::shutters->getLastPos == $FHEM::Automation::ShuttersControl::shutters->getSleepPos
                        ? $FHEM::Automation::ShuttersControl::shutters->getOpenPos
                        : $FHEM::Automation::ShuttersControl::shutters->getLastPos
                      )
                    : $FHEM::Automation::ShuttersControl::shutters->getOpenPos
                )
            )
        );

        \&FHEM::Automation::ShuttersControl::ASC_Debug( 'ShadingProcessingDriveCommand: '
              . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
              . ' - Der aktuelle Beschattungsstatus ist: '
              . $FHEM::Automation::ShuttersControl::shutters->getShadingStatus
              . ' und somit wird nun in die Position: '
              . $getShadingPos
              . ' zum beenden der Beschattung gefahren' );
    }

    Log3( $name, 4,
"AutoShuttersControl ($name) - Shading Processing - In der Routine zum fahren der Rollläden, Shading Wert: "
          . $FHEM::Automation::ShuttersControl::shutters->getShadingStatus );

    \&FHEM::Automation::ShuttersControl::ASC_Debug(
            'ShadingProcessingDriveCommand: '
          . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
          . ' - Der aktuelle Beschattungsstatus ist: '
          . $FHEM::Automation::ShuttersControl::shutters->getShadingStatus
          . ', Beschattungsstatus Zeitstempel: '
          . strftime(
            "%Y.%m.%e %T", localtime( $FHEM::Automation::ShuttersControl::shutters->getShadingStatusTimestamp )
          )
    );

    return;
}
