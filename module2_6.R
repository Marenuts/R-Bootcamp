
##################################################
####                                          ####  
####  R Bootcamp, Module 2.6                  ####
####                                          #### 
####   University of Nevada, Reno             ####
####                                          #### 
##################################################


######################################################
####  Introduction to Spatial Data Analysis in R  ####
####     Facilitator: Mitch Gritts                ####
######################################################


###################
# before starting make sure we have a clean global environment
rm(list = ls())

# load libraries and set working directory
library(dplyr)
library(sp)
library(raster)
library(rgdal)
library(rgeos)
library(ggthemes)
library(magrittr)
library(leaflet)


# create spatial points data frame ----
## load reptile data 
reptiles <- readr::read_csv('reptiles.csv')

## create a SpatialPoints object
sp_points <- SpatialPoints(
  coords = reptiles[, c('x', 'y')]
)

## inspect the SpatialPoints object
str(sp_points)


# add a projection to a spatial object ----
## create a CRS object
utm <- CRS('+init=epsg:26911')

## add the projection to sp_points
sp_points@proj4string <- utm

## inspect SpatialPoints
str(sp_points)


# add data to sp_points ----
spdf_points <- SpatialPointsDataFrame(coords = sp_points, data = reptiles)

## inspect the data
str(spdf_points)


# subset a SpatialPointsDataFrame ----
## first, inspect the data in the @data slo
head(spdf_points@data)

## great, it looks just like a data.frame
## lets look at the species column, I'll only return the first 10
spdf_points@data$species[1:10]

## another way to do this
spdf_points$species[1:10]

## or, another method
spdf_points@data[1:10, 'species']

## cool, this thing behaves just like a data frame. Lets subset it.
## create a variable to hold our species of interest
phpl <- 'Phrynosoma platyrhinos'

## then subset the data...
phpl_spdf <- spdf_points[spdf_points$species == phpl, ]

## check to see that there is only one species in the data.frame
phpl_spdf %>% magrittr::extract2('species') %>% unique()


# one step to create a SpatialPointsDataFrame ----
spdf1 <- SpatialPointsDataFrame(
  coords = reptiles[, c('x', 'y')],
  data = reptiles,
  proj4string = utm
)
 # str(spdf1, max.level = 2)

## and lets clean up the global env
rm(phpl_spdf, reptiles, sp_points, spdf1, phpl)


#############
# Nevada Counties example...

# read in nv county shapefile ----
counties <- shapefile('data/nv_counties/NV_Admin_Counties.shp')

## once finished check the structure
# str(counties, max.level = 3)

## some data management
### check the proj4string
counties@proj4string

### this proj4string, while encoding the same projection isn't identical to 
### the proj4string of spdf_points
spdf_points@proj4string

identicalCRS(counties, spdf_points)

### let's coerce the points to our desired CRS, utm
### this will throw a warning because we counties already has a projection
### and we are forcing a new (albeit same) projection onto it. This isn't
### the same as reprojecting, which we will get to later
proj4string(counties) <- utm


## check structure of a polygon within a SpatialPolygonsDataFrame
str(counties@polygons[[1]])


## plot a spatial polygon
plot(counties, col = 'springgreen', border = 'purple', lwd = 3)

## we can plot certain polygons...
layout(matrix(1:3, ncol = 3, nrow = 1))
plot(counties[1, ])
plot(counties[1:4, ])
plot(counties[counties$CNTYNAME == 'Clark', ])

## we can even plot our reptile points ontop of the counties
layout(matrix(1))
plot(counties)
points(spdf_points, pch = 1, cex = .5, col = 'purple')


# Spatial joins ----

## use the %over% funcstion, which is the same as over(spdf_points, counties)
rslt <- spdf_points %over% counties

## what does rslt look like?
str(rslt)


## bind data in rslt to spdf_points
spdf_points$county <- rslt$CNTYNAME

## remember back to one of our plot above that some points
## fall outside nevada
plot(counties)
points(spdf_points, col = 'purple')

## lets remove those from our dataset, as we shouldn't have any collections
## outside nevada and these are data entry mistakes
spdf_points <- spdf_points[!(is.na(spdf_points$county)), ]

## now lets plot, for fun
plot(counties)
points(spdf_points[spdf_points$county == 'Clark', ], col = 'springgreen', cex = .5)


# create a study grid ----
bb <- counties@bbox

## this code is used to create a SpatialPolygonsDataFrame grid
## it isn't important that you understand it right now
grd <- GridTopology(
  cellcentre.offset = c(bb[1, 1] + 50000, bb[2, 1]), 
  cellsize = c(150000, 150000),
  cells.dim = c(4, 6)
)

p_grd <- SpatialPolygonsDataFrame(
  Sr = as.SpatialPolygons.GridTopology(grd),
  data = data.frame('study_area' = 1:24),
  match.ID = F)
proj4string(p_grd) <- utm

## plot the  grid and counties
layout(matrix(1:2, nrow = 1, ncol = 2))
plot(p_grd)
text(coordinates(p_grd), label = row.names(p_grd))

plot(counties)
text(coordinates(counties), label = counties$CNTYNAME, cex = .75)


# intersect 2 polygon geometries ----
## a little data management to make the intersection easier
row.names(counties) <- counties$COV_NAME

## intersect the geometries
intersect <- gIntersection(counties, p_grd, byid = T)

## plot the result, color to show that they are separate
plot(intersect, col = blues9)

## check the structure
str(intersect, max.level = 2)


# getting our data back from the intersection ----
## check the row.names of these polygons
row.names(intersect)

## these appear to be a concat of the first geometries row.names, and 
## the second geometries row.names. We can work with that to get our data
## strsplit returns a list
tmp <- strsplit(row.names(intersect), split = ' ')


## iterate over the list to get either the 1st or 2nd element
county_name <- sapply(tmp, '[[', 1)
study_area <- sapply(tmp, '[[', 2)

## now we now which county and study area each polygon belongs to
## store this data in a data.frame
df_names <- data.frame(county_name = county_name, study_area = study_area, row.names = row.names(intersect))

## let's add the area of each polygon to this data.frame
## remember that the area for each polygon is stored
## with each Polygon object, and is in square meters
## below we will get the area and convert it to square kilometers
intersect@polygons[[1]]@area / 1e6

## lets iterate over the object to get this data
parea <- sapply(seq_along(intersect), function (i) intersect@polygons[[i]]@area / 1e6)
df_names$area <- parea

## finally, create a SpatialPolygonsDataFrame
new_polys <- SpatialPolygonsDataFrame(Sr = intersect, data = df_names)

## and just for completions sake... plot it
layout(matrix(1:3, nrow = 1, ncol = 3))
### plot colored by county
plot(new_polys, col = ggthemes::gdocs_pal()(17)[new_polys$county_name])

### plot colored by study area
plot(new_polys, col = ggthemes::gdocs_pal()(20)[new_polys$study_area])

### plot differentiating each polygon
plot(new_polys, col = blues9)


# Everything in R is a function call, almost ----
## are the following equal?
1 + 1 == `+`(1, 1)

## how about these?
county_name[[1]] == `[[`(county_name, 1)


# unioning polygons ----
## all of these function come from the rgeos package.
## select two counties to union
plot(counties[2:3, ])

## union them
nnv <- gUnion(counties[2, ], counties[3, ])

## plot the result
plot(nnv)

## inspect
str(nnv)

rm(nnv)

# union all interior polygons ----
## we ccan do the same thing to get a the border of NV
## use a different function, but same idea
nv <- gUnaryUnion(counties)
plot(nv)


# spTranform ----
## reproject
wgs_pts <- spTransform(spdf_points, CRS('+init=epsg:4326'))

## inspect coordinates
wgs_pts@coords[1:5, 1:2]

## we can do this to polygons too
wgs_counties <- spTransform(counties, CRS('+init=epsg:4326'))

## then we can plot the two counties projection side by side
layout(matrix(1:2, nrow=1, ncol=2))

plot(counties, main = 'UTM NAD83 zone 11')
plot(wgs_counties, main = 'WGS84')


## we can do this with other reprojections as well so you can really tell a difference
layout(matrix(1:8, nrow = 2, ncol = 4))
plot(spTransform(counties, CRS('+proj=aea')), main = 'Albers Equal Area', sub = 'USGS')
plot(spTransform(counties, CRS('+proj=sinu')), main = 'Van Der Grinten')
plot(spTransform(counties, CRS('+proj=robin')), main = 'Robinson')
plot(spTransform(counties, CRS('+proj=isea')), main = 'Icosahedral Snyder', sub = 'Dymaxion, Butterfly not open source')
plot(spTransform(counties, CRS('+proj=wintri')), main = 'Winkel-Tripel', sub = 'National Geographic')
plot(spTransform(counties, CRS('+proj=goode')), main = 'Goode Homolosine')
plot(spTransform(counties, CRS('+proj=eqc')), main = 'Plate Carree')
plot(spTransform(counties, CRS('+proj=gall')), main = 'Gall-Peters')


# working with raster data ----
## save some data for later
save(counties, spdf_points, wgs_pts, file = 'data/module2_6.RData')

## let's clean our workspace first
rm(bb, df_names, grd, intersect, new_polys, nnv, p_grd, rslt, tmp, wgs_counties, county_name, parea, study_area, counties, spdf_points, wgs_pts)

## load a raster
dem <- raster('data/nv_dem_coarse.grd')

## check dem structure
str(dem)

## what is this?
dem@data@inmemory


## plot raster
plot(dem)

## or
image(dem, asp = 1)


# load a second raster, distance to roads ----
road_rast <- raster('data/road_dist.grd')

## plot
plot(road_rast)


## use the raster::projection function
projection(road_rast)
projection(dem)
identicalCRS(road_rast, dem)

## compare to nv SpatialPolygonsDataFrame
identicalCRS(dem, nv)
projection(nv)

## proof these are the same crs
plot(dem)
plot(nv, lwd = 3, add = T)

## coerce projection
dem@crs <- nv@proj4string
road_rast@crs <- nv@proj4string
identicalCRS(dem, nv)

## check that we haven't screwed things up
plot(dem)
plot(nv, lwd = 3, add = T)


# create distance to roads ----
road_dist <- distance(road_rast, filename = "road_dist.grd", overwrite = T)

## cool, what does this look like?
plot(road_dist)


## mask raster to NV border. This will set all values outside NV to NA
nv_road_dist <- mask(road_dist, mask = nv, filename = 'nv_road_dist.grd', overwrite = T)

## plot our new raster, with nevada border
plot(nv_road_dist)
plot(nv, lwd = 3, add = T)

## compare raster values
summary(road_dist)
summary(nv_road_dist)


# raster extraction ----
## global env setup
rm(road_dist, road_rast)
load('data/module2_3.RData')
## the following command might not do anything, however there may be some additional data in the .RData file that we don't need
rm(counties, wgs_pts)


## create an extent object to limit the size of our raster plot
## wubset the points so we can see them
bounds <- extent(spdf_points[spdf_points$county == 'Humboldt', ])

## extend the extent object so all the points fit on the map
plot(dem, ext = extend(bounds, 10000))
points(spdf_points[spdf_points$county == 'Humboldt', ])


## extract values from the dem
## this returns a vector of length = nrow(spdf_points)
elevation <- raster::extract(dem, spdf_points)
summary(elevation)

## this can be combined with our data
## and yes, this can be done in one step instead of 2
spdf_points$elevation <- elevation


## and now, we can figure out the distribution of elevations in our data!
hist(spdf_points$elevation * 3.28, main = 'Distribution of Elevation', xlab = 'Elevation (ft)', freq = F)

## what about those NAs?
na_points <- spdf_points[is.na(spdf_points$elevation), ]
## honestly, this 2000 number is purely experimental, 
## change values till you get what you want on the map
bounds <- extend(extent(na_points), 2000)

## plot the map, zoom in on these points in the map
plot(dem, ext = bounds)
points(na_points)
plot(nv, add = T)


library(leaflet)
# interactive mapping ----
leaflet::leaflet(wgs_pts[1:100, ]) %>% 
  addTiles() %>% 
  addCircleMarkers(radius = 5)


## leaflet provider tiles
leaflet::leaflet(wgs_pts[1:100, ]) %>% 
  addProviderTiles(providers$Esri.WorldTopoMap) %>% 
  addCircleMarkers(radius = 5)


## and popups
leaflet::leaflet(wgs_pts[1:100, ]) %>% 
  addTiles() %>% 
  addCircleMarkers(radius = 5, popup = paste(wgs_pts$species[1:100]))


# SpatialLines solution ----
## 1. read in data
### HINT: use readshapefile
### data to use:
#### data/roads/roads.shp
#### data/counties/counties.shp

## 2. reproject
### HINT: check counties projection

## 3. plot

## 4. plot roads, style based on road type 

## 5. intersect counties and roads

## 6. plot some of the intersections

## etc ...

