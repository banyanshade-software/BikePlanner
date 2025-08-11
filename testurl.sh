#!/bin/sh

curl "https://brouter.de/brouter?lonlats=0.422829,44.086583%7C0.657371,44.348181&profile=trekking&alternativeidx=0&format=gpx" > t1.gpx
curl "https://brouter.de/brouter?lonlats=0.422829,44.086583%7C0.657371,44.348181&profile=trekking&alternativeidx=0&format=gpx&extraParams=profile:uphillcutoff=1.02&profile:uphillcost=900" > t2.gpx

diff t1.gpx t2.gpx
