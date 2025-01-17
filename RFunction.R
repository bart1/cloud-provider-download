# for loading move1, move2 or CSV files
# still allow moveStack objects...

# need to update to add (like in Upload from Local App) settings: time_col="timestamp", track_id_col="individual.local.identifier", track_attr="",coords="location.long,location.lat",crss=4326


library(move2)
library(move)
library(units)
# for reading files from disk
source("./src/io/rds.R")

rFunction = function(
    settings=NULL,                # MoveApps settings (unused)
    file=NULL,                    # MoveApps settings section `file` (unused)
    folder=NULL,                  # MoveApps settings section `folder` (unused)
    id=NULL,                      # The id of the file in the cloud-provider context
    fileId=NULL,                  # The id of the file (includes folder of file)
    fileName=NULL,                # The original file-name (in cloud and placed locally)
    mimeType=NULL,                # The mime-type of the file (unused)
    cloudFileLocalFolder="/tmp",  # local directory of cloud-file
    data=NULL,                     # The data of the prev. apps in the workflow
    time_col="timestamp",
    track_id_col="individual.local.identifier", 
    track_attr="",
    coords="location.long,location.lat",
    crss=4326
) {
  Sys.setenv(tz="UTC") #fix, so that time zones will be transformed into UTC (input RDS files (or data from prev app) with tz=NULL are forced to UTC) -> requires that timezone is UTC, add to documentation!
  
  if (! is.null(fileId)) {
    logger.info(paste("Download file '", fileId, "' from cloud provider.", sep = ""))
  }
  
  cloudSource <- NULL
  result <- NULL
  
  if (! is.null(fileName)) { 
    extn0 <- strsplit(fileName,"[.]")[[1]]
    extn <- extn0[length(extn0)]
    
    if (extn=="rds")
    {
      new1 <- readRdsInput(paste(cloudFileLocalFolder,"/",fileName,sep = ""))
      
      if(is.na(crs(new1))){
        new1 <- NULL
        logger.info("The uploaded rds file does not contain coordinate reference system information. This data set cannot be uploaded")
      }
      
      if(is.null(new1)){logger.info("No new rds data found.")
      } else { 
        # if .rds is move2
        if(any(class(new1)=="move2")){logger.info("Uploaded rds file containes a object of class move2")
          ## remove empty locations
          new1 <- new1[!sf::st_is_empty(new1),]  
          if(nrow(new1)==0){logger.info("Your uploaded csv file does not contain any location data.")}
          #### applying the same "cleaning" as for the move2 created from csv below, as someone can create a move2 in R and uploaded to moveapps. This object can contain empty coords, duplicates etc
          ## remove duplicated timestamps
          if(!mt_has_unique_location_time_records(new1)){
            n_dupl <- length(which(duplicated(paste(mt_track_id(new1),mt_time(new1)))))
            logger.info(paste("Your data has",n_dupl, "duplicated location-time records. We removed here those with less info and then select the first if still duplicated."))
            ## this piece of code keeps the duplicated entry with least number of columns with NA values
            new1 <- new1 %>%
              mutate(n_na = rowSums(is.na(pick(everything())))) %>%
              arrange(n_na) %>%
              mt_filter_unique(criterion='first') # this always needs to be "first" because the duplicates get ordered according to the number of columns with NA. 
          }
          
          ## ensure timestamps are ordered within tracks
          new1 <- dplyr::arrange(new1, mt_track_id(new1), mt_time(new1)) 
        }
        
        # if move2 object - fine, else transform moveStack to move2
        if(any(class(new1)=="MoveStack")){
          new1 <- mt_as_move2(new1)
          logger.info("Uploaded rds file containes a object of class moveStack that is transformed to move2.")
        }
        if(!any(class(new1)%in%c("move2","MoveStack"))){
          new1 <- NULL
          logger.info("Uploaded rds file contains data with unexpected class, please ensure that the file contains a object of class 'move2' or 'MoveStack'.")}
      }
      # make names for new1
      if(!is.null(new1)){
        names(new1) <- make.names(names(new1),allow_=TRUE)
        mt_track_id(new1) <- make.names(mt_track_id(new1),allow_=TRUE)
      }
      cloudSource <- new1

    } else if (extn == "csv")
    {
      test <- readLines(paste(cloudFileLocalFolder,"/",fileName,sep = "")) #to check if it is empty, only continue if not
      if (test[1]=="")
      {
        df2 <- NULL
        logger.info("No new csv data found. The settings of the App are not used.")
        
      } else
      {
        df2 <-  vroom::vroom(paste(cloudFileLocalFolder,"/",fileName,sep = ""), delim = ",") # alternative to read.csv, takes care of timestamps, default timezome is UTC, problems with empty table avoided above
        if(length(grep(",",coords)) %in% c(1,2)){
          coo <- trimws(strsplit(as.character(coords),",")[[1]])
          logger.info(paste("You have defined as coordinate columns:",coords))
        } else {
          coo <- NULL
          logger.info("An incorrect number of coordinate columns is provided; expecting two (x,y) or three (x,y,z). Cannot transform csv data to move2.")
          df2 <- NULL
        }
        if(!is.null(df2)){
          logger.info("New data uploaded from csv file, this file is expected to be comma delimited.")
          logger.info(paste("You have defined as datetime column: ",time_col,".", " The expected timestamp format is 'yyyy-mm-dd HH:MM:SS' and in UTC timezone"))
          logger.info(paste("You have defined as track ID column: ",track_id_col,"."))
          logger.info(paste("You have defined as track attributes: ",track_attr,"."))
          logger.info(paste("You have defined as projection (crs): ",crss,".", " The expected projection is a valid numeric EPSG value. For more info see https://epsg.io/ and https://spatialreference.org/"))
          
          #this only if a comma in the data!
          if(length(grep(",",track_attr))>0){tr_attr <- trimws(strsplit(as.character(track_attr),",")[[1]])} else {tr_attr <- track_attr}
          
          # transform data.frame to move2 object
          df2 <- dplyr::filter(df2,!is.na(df2[[track_id_col]])) # if there is a NA in the track_id col, mt_as_move2() gives error
          n.trcolna <- length(which(is.na(df2[[track_id_col]])))
          if (n.trcolna>0) logger.info(paste("Your tracks contained",ntrcolna,"locations with unspecified track ID. They have been removed."))
          new2 <- mt_as_move2(df2,
                              time_column=time_col,
                              track_id_column=track_id_col,
                              track_attributes=track_attr,
                              coords=coo,
                              crs=crss,
                              na.fail=FALSE)
          ## remove empty locations
          new2 <- new2[!sf::st_is_empty(new2),]  
          if(nrow(new2)==0){logger.info("Your uploaded csv file does not contain any location data.")}
          
          ## remove duplicated timestamps
          if(!mt_has_unique_location_time_records(new2)){
            n_dupl <- length(which(duplicated(paste(mt_track_id(new2),mt_time(new2)))))
            logger.info(paste("Your data has",n_dupl, "duplicated location-time records. We removed here those with less info and then select the first if still duplicated."))
            ## this piece of code keeps the duplicated entry with least number of columns with NA values
            new2 <- new2 %>%
              mutate(n_na = rowSums(is.na(pick(everything())))) %>%
              arrange(n_na) %>%
              mt_filter_unique(criterion='first') # this always needs to be "first" because the duplicates get ordered according to the number of columns with NA. 
          }
          
          ## ensure timestamps are ordered within tracks
          new2 <- dplyr::arrange(new2, mt_track_id(new2), mt_time(new2)) 
          
          # make names for new2
          names(new2) <- make.names(names(new2),allow_=TRUE)
          mt_track_id(new2) <- make.names(mt_track_id(new2),allow_=TRUE)
      }
    }
    if(is.null(df2)) new2 <- NULL else if (nrow(new2)==0) new2 <- NULL
    cloudSource <- new2
    
  } else 
  {
      logger.info("The extension of your uploaded file is neither `csv` nor `rds`. This App cannot work with other files, NULL will be returned.")
      cloudSource <- NULL
  }
    
    result <- cloudSource
  }
  
  if (exists("data") && !is.null(data)) {
    logger.info("Merging input from previous App and cloud file together.")
    
    #drop units from intersecting columns that are not defined as time/loc/track_ID
    defd <- c(time_col,track_id_col,trimws(strsplit(as.character(coords),",")[[1]]),"geometry")
    overlp <- intersect(names(result), names(data))
    drp <- overlp[!is.element(overlp,defd)]
    if (length(drp>0)) 
    {
      for (i in seq(along=drp)) 
      {
        dataunit <- eval(parse(text=paste("class(data$",drp[i],")=='units'",sep="")))
        resultunit <- eval(parse(text=paste("class(result$",drp[i],")=='units'",sep="")))
        
        if (dataunit & !resultunit) eval(parse(text=paste("data$",drp[i],"<- drop_units(data$",drp[i],")",sep=""))) #if only the variable in data has units, drop them
        if (resultunit & !dataunit) eval(parse(text=paste("result$",drp[i],"<- drop_units(result$",drp[i],")",sep=""))) #if only the variable in result has units, drop them
      }
    }
    
    result <- mt_stack(result, data, .track_combine="rename",.track_id_repair="universal")
    
  } else {
    logger.info("No input from previous App provided, nothing to merge. Will deliver the mapped cloud-file only.")
  }
  
  logger.info("I'm done.")
  return(result)
}
