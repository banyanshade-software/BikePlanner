#!/bin/sh

#curl "https://brouter.de/brouter?lonlats=0.422829,44.086583%7C0.657371,44.348181&profile=trekking&alternativeidx=0&format=gpx" > t1.gpx
#curl "https://brouter.de/brouter?lonlats=0.422829,44.086583%7C0.657371,44.348181&profile=trekking&alternativeidx=0&format=gpx&extraParams=profile:uphillcutoff=1.02&profile:uphillcost=900" > t2.gpx

#diff t1.gpx t2.gpx

curl -i 'https://brouter.de/brouter?lonlats=0.457685,44.130880%7C0.982019,44.187506&profile=trekking&alternativeidx=0&format=gpx&extraParams=validForBikes=true&allow_steps=true&allow_ferries=true&ignore_cycleroutes=false&stick_to_cycleroutes=false&avoid_unsafe=false&add_beeline=false&consider_noise=false&consider_river=false&consider_forest=false&consider_town=false&consider_traffic=false&consider_elevation=true&downhillcost=60&downhillcutoff=1.5&uphillcost=0&uphillcutoff=1.5&totalMass=90&maxSpeed=45&S_C_x=0.225&C_r=0.01&bikerPower=100&turnInstructionMode=1&turnInstructionCatchingRange=40&turnInstructionRoundabouts=true&considerTurnRestrictions=true&processUnusedTags=false&classifier_none=1&classifier_ferry=2'
