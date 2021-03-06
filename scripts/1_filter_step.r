###Filtering data after variant calling analyses###

#The Population Genetics and Genomics in R Primer (https://grunwaldlab.github.io/Population_Genetics_in_R/index.html) was referenced.
#The unfiltered VCF file and metadata table are also available in the 'data' folder. 
#Raw demultiplexed FASTQ files have been deposited into NCBI SRA (BioProject accession number PRJNA734954)

library(reshape2)
library(ggplot2) 
library(cowplot)
library(vcfR)
library(poppr)
library(ape)
library(RColorBrewer)
library(gdata)

#Visualization of read depth
setwd("~/tomato_leaf_mold/")
pass.vcf = read.vcfR("data/passalora_4_2.vcf")
dp <- extract.gt(pass.vcf, element = "DP", as.numeric=TRUE)
dpf <- melt(dp, varnames=c('Index', 'Sample'), value.name = 'Depth', na.rm=TRUE)
dpf <- dpf[ dpf$Depth > 0,]
samps_per_row <- 20
myRows <- ceiling(length(levels(dpf$Sample))/samps_per_row)
myList <- vector(mode = "list", length = myRows)
for(i in 1:myRows){
  myIndex <- c(i*samps_per_row - samps_per_row + 1):c(i*samps_per_row)
  myIndex <- myIndex[myIndex <= length(levels(dpf$Sample))]
  myLevels <- levels(dpf$Sample)[myIndex]
  myRegex <- paste(myLevels, collapse = "$|^")
  myRegex <- paste("^", myRegex, "$", sep = "")
  myList[[i]] <- dpf[grep(myRegex, dpf$Sample),]
  myList[[i]]$Sample <- factor(myList[[i]]$Sample)
}

myPlots <- vector(mode = "list", length = myRows)
for(i in 1:myRows){
  myPlots[[i]] <- ggplot(myList[[i]], aes(x=Sample, y=Depth)) + 
                  geom_violin(fill="#8dd3c7", adjust=1.0, scale = "count", trim=TRUE)

  myPlots[[i]] <- myPlots[[i]] + theme_bw()
  myPlots[[i]] <- myPlots[[i]] + theme(axis.title.x = element_blank(), 
                  axis.text.x = element_text(angle = 60, hjust = 1))
  myPlots[[i]] <- myPlots[[i]] + scale_y_continuous(trans=scales::log2_trans(), 
                  breaks=c(1, 10, 100, 800),
                  minor_breaks=c(1:10, 2:10*10, 2:8*100))
  myPlots[[i]] <- myPlots[[i]] + theme( panel.grid.major.y=element_line(color = "#A9A9A9", size=0.6) )
  myPlots[[i]] <- myPlots[[i]] + theme( panel.grid.minor.y=element_line(color = "#C0C0C0", size=0.2) )
}
plot_grid(plotlist = myPlots, nrow = myRows)


#Initial filtering based on read depth
quants <- apply(dp, MARGIN=2, quantile, probs=c(0.05, 0.95), na.rm=TRUE)
dp2 <- sweep(dp, MARGIN=2, FUN = "-", quants[1,])
dp[dp2 < 0] <- NA
dp2 <- sweep(dp, MARGIN=2, FUN = "-", quants[2,])
dp[dp2 > 0]<- NA
dp[dp < 5] <- NA
dp[dp > 100] <- NA
pass.vcf@gt[,-1][ is.na(dp) == TRUE ] <- NA
pass.vcf

#Omitting samples based on percentage of missing data
myMiss <- apply(dp, MARGIN = 2, function(x){ sum( is.na(x) ) } )
myMiss <- myMiss / nrow(dp)
pass.vcf@gt <- pass.vcf@gt[, c(TRUE, myMiss < 0.55)]
dp <- extract.gt(pass.vcf, element = "DP", as.numeric=TRUE)
heatmap.bp(dp[1:1000,], rlabels = FALSE)
pass.vcf

#Omitting variants
dp <- extract.gt(pass.vcf, element = "DP", as.numeric=TRUE)
myMiss <- apply(dp, MARGIN = 1, function(x){ sum( is.na(x) ) } )
myMiss <- myMiss / ncol(dp)
hist(myMiss, col = "#8DD3C7", xlab = "Missingness (%)")
pass.vcf <- pass.vcf[myMiss < 0.2, ]

#Visualizing filtered data
dp <- extract.gt(pass.vcf, element = "DP", as.numeric=TRUE)
heatmap.bp(dp[1:1000,], rlabels = FALSE)
dpf <- melt(dp, varnames = c("Index", "Sample"),
            value.name = "Depth", na.rm = TRUE)
dpf <- dpf[ dpf$Depth > 0, ]
p <- ggplot(dpf, aes(x = Sample, y = Depth))
p <- p + geom_violin(fill = "#C0C0C0", adjust = 1.0,
                     scale = "count", trim = TRUE)
p <- p + theme_bw()
p <- p + theme(axis.title.x = element_blank(),
               axis.text.x = element_text(angle = 60, hjust = 1))
p <- p + scale_y_continuous(trans = scales::log2_trans(),
                            breaks = c(1, 10, 100, 800),
                            minor_breaks = c(1:10, 2:10 * 10, 2:8 * 100))
p <- p + theme(panel.grid.major.y = element_line(color = "#A9A9A9", size = 0.6))
p <- p + theme(panel.grid.minor.y = element_line(color = "#C0C0C0", size = 0.2))
p <- p + ylab("Depth (DP)")
p

#Retain only non-heterozygous positions, as well as biallelic and polymorphic positions
#Remove heterozygous positions
gt <- extract.gt(pass.vcf)
hets <- is_het(gt)
is.na(pass.vcf@gt[,-1][is_het(gt)]) <- TRUE
gt <- extract.gt(pass.vcf)

#Retaining only the biallelic positions 
pass.vcf <- pass.vcf[is.biallelic(pass.vcf)]
# Retaining only the polymorphic sites
pass.vcf <- pass.vcf[is.polymorphic(pass.vcf, na.omit = T),]
pass.vcf

#Filtering by minor allele frequency
mymaf <- maf(pass.vcf, element = 2)
mymaf <- mymaf[mymaf[,4] > 0.05,]
fix <- pass.vcf@fix[pass.vcf@fix[,3] %in% rownames(mymaf), ]
nrow(fix)
pass.vcf@fix <- fix
nrow(pass.vcf@fix)
true_ind <- which(pass.vcf@fix[,3] %in% rownames(mymaf))
pass.vcf@fix <- pass.vcf@fix[true_ind, ]
pass.vcf@gt <- pass.vcf@gt[true_ind, ]
pass.vcf
write.vcf(pass.vcf, file = "filteredpfulva.vcf.gz")

#Obtain information about % missing data for each sample. This is useful for determining which of the technical replicates to retain or discard in the final analysis
myMiss <- apply(dp, MARGIN = 2, function(x){ sum(is.na(x)) })
myMiss <- myMiss/nrow(pass.vcf)
write.csv(myMiss, file = "missingnesspfulva")

#Remove replicate isolates from dataset, based on % missing data
copy1 = read.vcfR("filteredpfulva.vcf.gz")
copy1@gt <- copy1@gt[, !colnames(copy1@gt) %in% c("pf78-2", "pf81-2", "pf77", "pf79", "19001-2", "17035", "19016-2", "19018-2", "pf92", "17052-2","19006-2")]
write.vcf(copy1,file = "filteredpfulvanodup.vcf.gz")
