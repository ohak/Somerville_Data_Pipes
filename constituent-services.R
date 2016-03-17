#### Created 3/16 by Daniel Hadley to download and upload Somerville's 311 data ####


# working Directory: the part you change for your machine #
setwd("c:/Users/dhadley/Documents/GitHub/Somerville_Data_Pipes/")

# This pulls in the credentials you need
source("./config.R")


library(RCurl)
library(dplyr)
library(tidyr)
library(jsonlite)
library(lubridate)
library(httr) # Upload to Socrata


#### Load Data & Update via QSend API ####

## Load old data from SomerStat shared drive ##
# I leave out reqcustom because it is massive and worthless
activity <- read.csv("//fileshare1/Departments2/Somerstat Data/Constituent_Services/data/activity.csv")
submitter <- read.csv("//fileshare1/Departments2/Somerstat Data/Constituent_Services/data/submitter.csv")
request <- read.csv("//fileshare1/Departments2/Somerstat Data/Constituent_Services/data/request.csv")
# reqcustom <- read.csv("//fileshare1/Departments2/Somerstat Data/Constituent_Services/data/reqcustom.csv")


# Changes since x using the Qscend API
# I do five days ago in case there is a problem for one or two days with the system
since <- Sys.Date() - 5

api <- paste("https://somervillema.qscend.com/qalert/api/v1/requests/changes/?since=", month(since), "%2F", day(since), "%2F", year(since), "&key=", Qsend_API_key, sep = "")

d <- fromJSON(api)

activityChanges <- d$activity
submitterChanges <- d$submitter
requestChanges <- d$request
# reqcustomChanges <- d$reqcustom


## Now merge the dataframes ##

# Merge and get rid of dupes for activity
activityUpdated <- rbind(activity, activityChanges)
activityUpdated <- distinct(activityUpdated)
# see above about reqcustom : it is massive and worthless
# reqcustomUpdated <- rbind(reqcustom, reqcustomChanges)
# reqcustomUpdated <- distinct(reqcustomUpdated)

# Overwrite for request & submitter
# A clever method: 
# http://stackoverflow.com/questions/28282484/join-two-dataframes-and-overwrite-matching-rows-r
requestUpdated <- rbind(requestChanges, request[!request$id %in% requestChanges$id,])
submitterUpdated <- rbind(submitterChanges, submitter[!submitter$id %in% submitterChanges$id,])




#### Write it ####

# Write it to the P: drive 
write.csv(requestUpdated, "//fileshare1/Departments2/Somerstat Data/Constituent_Services/data/request.csv", row.names = FALSE)

write.csv(activityUpdated, "//fileshare1/Departments2/Somerstat Data/Constituent_Services/data/activity.csv", row.names = FALSE)

write.csv(submitterUpdated, "//fileshare1/Departments2/Somerstat Data/Constituent_Services/data/submitter.csv", row.names = FALSE)

# write.csv(reqcustomUpdated, "//fileshare1/Departments2/Somerstat Data/Constituent_Services/data/reqcusreqcustom.csv", row.names = FALSE)


# Remove everything else
remove(activity, activityChanges, request, requestChanges, submitter, submitterChanges, reqcustom, reqcustomChanges, d)


#### Prepare a singe datset for upload to Socrata and elsewhere ####
# the summarise is the way to get the latest action by using which.max
# we get rid of all the admin type actions, because those are of no interest to the public
lastAction <- activityUpdated  %>%
  filter(codeDesc %in% c("Closed", "Created", "Re-opened")) %>% 
  group_by(requestId) %>% 
  summarise(LastAction = codeDesc[which.max(id)],
            dateLastAction = displayDate[which.max(id)])


d <- merge(requestUpdated, lastAction, by.x = "id", by.y = "requestId")

#### Narrow down to useful columns for saving in various locations ####
# I drop displayLastAction because it is not the same as the date I create above
# Because above I take out things like "printed"
# Who cares when it was printed?!? That's not an action
d <- d %>% 
  select(id, cityName, comments, dept, displayDate, district, latitude, longitude, streetId: dateLastAction)


# Create a more general 'type' column from the #s given to me by S. Craig
# Call it the weird name because that is a socrata convention
serviceRequests <- c(269, 422,424,492,425,503, 504,427,428,272,417,418,475,419,420,421, 273,274,493,494,271, 495,496,413,414,415,502,497,498,471,499,500,501,506,507,508,509,510,511,505,512,275,580,482,315,316, 317,276,466,299,301,488,302,303,304,305,307,308,277,310,311,594,467,483,484,278,322,437,438,439,440,441,442,443,338,444,445,446,447,340,448,449,450,451,470,452,341,453,454,456,455,457,458,459,460,461,462,464,465,463,339,280,360,346,347,348,349,361,364,318,350,351,352,353,366,365,386,367,358,402663,370,371,369,281,289,290,294,293,295,282,284,550,588,400324,435,287)

informationCalls <- c(526,373,378,581,527,528,589,591,532,579,582,530,534,587,531,412,411,381,382,533,535,536,539,540,542,541,578,400135,374,400049,401190,400445,401978,389,390,391,392,393,376,400127,394,395,396,544,546,398,399,402,403,408,409,543,547,548,404,400074,400604,549,401953,401775,401951,586,597,596,400464,598,400466,599,600,590,603,604,605,606,601,602,400254,552,553,554,555,556,557,559,560,570,563,564,565,566,567,568,569,561,571,572,573)

DPWInternal <- c(473,476,474,402500,475,481,477,487,478,470,480)

d$secondary_issue_type <- ifelse(d$typeId %in% serviceRequests, "Service Requests", 
                                 ifelse(d$typeId %in% informationCalls, "information calls",
                                        ifelse(d$typeId %in% DPWInternal, "DPW Internal", NA)))


### Write the final data
write.csv(d, "//fileshare1/Departments2/Somerstat Data/Constituent_Services/data/311_Somerville.csv", row.names = FALSE)




#### Upload to Socrata ####
d_311 <- d

# Get rid of NAs because they cause problems on Socrata's end
d_311_For_Socrata <- d_311 %>%
  mutate(neighborhood_district = paste("Ward", substring(district, 1, 1)), 
         neighborhood_district = ifelse(neighborhood_district == "Ward ", "", neighborhood_district),
         ticket_closed_date_time = dateLastAction,
         location = paste(streetNum, " ", streetName, ", ", "Somerville, MA", " (", latitude, ", ", longitude, ")", sep=""),
         street_address = paste(streetNum, " ", streetName, sep=""),
         ticket_status = ifelse(LastAction != "Closed", "Open", "Closed")) %>%
  rename(ticket_id = id, issue_description = dept, issue_type = typeName, city = cityName, ticket_created_date_time = displayDate, ticket_last_updated_date_time = dateLastAction) %>% 
  select(-comments, -streetId, -streetName, -streetNum, -district, -city, -latitude, -longitude, -typeId, -LastAction)

# Fix addresses
# d_311_For_Socrata$Location_1 = gsub("NA, Somerville, MA \\(0, 0\\)", NA, d_311_For_Socrata$Location_1)
# This line above works, but throws errors on PUT requests when Socrata cannot geocode


# IF not closed, give NA for closed date and time
d_311_For_Socrata$ticket_closed_date_time[d_311_For_Socrata$ticket_status != "Closed"] <- ""

# Write locally
write.csv(d_311_For_Socrata, "./tmp/311.csv", row.names = FALSE, na = "")


## We also needed just the work orders to make the 311 app work better
d_311_For_Socrata_Just_WO <- d_311_For_Socrata %>% 
  filter(secondary_issue_type == "Service Requests")

# Write locally
write.csv(d_311_For_Socrata_Just_WO, "./tmp/311_Just_WO.csv", row.names = FALSE, na = "")


# Upload to Socrata
PUT("https://data.somervillema.gov/resource/vqwi-n3ah.json",
    body = upload_file("./tmp/311.csv"),
    authenticate(Socrata_username, Socrata_password), 
    add_headers("X-App-Token" = Socrata_token,
                "Content-Type" = "text/csv"))

# Now just work orders
PUT("https://data.somervillema.gov/resource/xs7t-pxkc.json",
    body = upload_file("./tmp/311_Just_WO.csv"),
    authenticate(Socrata_username, Socrata_password), 
    add_headers("X-App-Token" = Socrata_token,
                "Content-Type" = "text/csv"))









# Footnotes
# #### The initial Data dump ####
# # QSend API undocumented method to get all data
# 
# api <- "https://somervillema.qscend.com/qalert/api/v1/requests/dump/?start=7%2F1%2F2015&key=5c2b987d13cc414cb26f956cf31fbffc8ca62dc37d1a4f6bba3cc74398162db5"
# 
# d <- fromJSON(api)
# 
# request <- d$request
# activity <- d$activity
# attachment <- d$attachment
# submitter <- d$submitter
# deleted <- d$deleted
# reqcustom <- d$reqcustom
# 
# write.csv(request, "./data/2015_08_20_Qalert_Data_Dump/request.csv", row.names = FALSE)
# write.csv(activity, "./data/2015_08_20_Qalert_Data_Dump/activity.csv", row.names = FALSE)
# write.csv(attachment, "./data/2015_08_20_Qalert_Data_Dump/attachment.csv", row.names = FALSE)
# write.csv(submitter, "./data/2015_08_20_Qalert_Data_Dump/submitter.csv", row.names = FALSE)
# write.csv(deleted, "./data/2015_08_20_Qalert_Data_Dump/deleted.csv", row.names = FALSE)
# write.csv(reqcustom, "./data/2015_08_20_Qalert_Data_Dump/reqcustom.csv", row.names = FALSE)
