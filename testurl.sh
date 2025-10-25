#!/bin/sh

curl -i "https://brouter.de/brouter?lonlats=0.879099,44.275107%7C0.512465,44.028731&profile=trekking&alternativeidx=0&format=gpx" > t1
curl -i "https://brouter.de/brouter?lonlats=0.879099,44.275107%7C0.512465,44.028731&profile=trekking&alternativeidx=0&format=gpx&extraParams=profile:uphillcost=200&profile:uphillcutoff=1.01" > t2


#curl -i "https://brouter.de/brouter?lonlats=1.337713,43.598687%7C1.824027,44.276550&profile=trekking&alternativeidx=0&format=gpx" > t1

#curl -i "https://brouter.de/brouter?lonlats=1.337713,43.598687%7C1.824027,44.276550&profile=trekking&alternativeidx=0&format=gpx&extraParams=avoid_unsafe=1" > t2
#curl -i "https://brouter.de/brouter?lonlats=1.337713,43.598687%7C1.824027,44.276550&profile=trekking&alternativeidx=0&format=gpx&extraParams=avoid_unsafe=0" > t3
#curl -i "https://brouter.de/brouter?lonlats=1.337713,43.598687%7C1.824027,44.276550&profile=trekking&alternativeidx=0&format=gpx&extraParams=avoid_unsafe=true&profile:uphillcost=200&profile:uphillcutoff=1.01" > t4


#curl "https://brouter.de/brouter?lonlats=0.422829,44.086583%7C0.657371,44.348181&profile=trekking&alternativeidx=0&format=gpx" > t1.gpx
#curl "https://brouter.de/brouter?lonlats=0.422829,44.086583%7C0.657371,44.348181&profile=trekking&alternativeidx=0&format=gpx&extraParams=profile:uphillcutoff=1.02&profile:uphillcost=900" > t2.gpx

#diff t1.gpx t2.gpx

#curl -i 'https://brouter.de/brouter?lonlats=0.457685,44.130880%7C0.982019,44.187506&profile=trekking&alternativeidx=0&format=gpx&extraParams=validForBikes=true&allow_steps=true&allow_ferries=true&ignore_cycleroutes=false&stick_to_cycleroutes=false&avoid_unsafe=false&add_beeline=false&consider_noise=false&consider_river=false&consider_forest=false&consider_town=false&consider_traffic=false&consider_elevation=true&downhillcost=60&downhillcutoff=1.5&uphillcost=0&uphillcutoff=1.5&totalMass=90&maxSpeed=45&S_C_x=0.225&C_r=0.01&bikerPower=100&turnInstructionMode=1&turnInstructionCatchingRange=40&turnInstructionRoundabouts=true&considerTurnRestrictions=true&processUnusedTags=false&classifier_none=1&classifier_ferry=2'




