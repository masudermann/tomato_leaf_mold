###Clone correction using pairwise identity by state analysis###

#This script takes a 012 formatted file (input: filtered vcf). This was done using VCFtools.  A pairwise IBS similarity matrix is produced, which is used to identify which isolates have unique genotypes.
#The script was modified with permission from Vogel et al. 2020-"Genome-wide association study in New York Phytophthora capsici isolates reveals loci involved in mating type and mefenoxam sensitivity".

library(igraph)
library(vcfR)

#Load 012 FILES (obtained from Vcftools 012 output. Input was the filtered vcf file)
setwd("~/tomato_leaf_mold")
snps <- read.table("012_format/6_5.012.pos")
indvs <- read.table("012_format/6_5.012.indv", stringsAsFactors = F)
indvs <-unlist(indvs$V1)
geno <- read.table("012_format/6_5.012")
print("geno loaded")
geno <- geno[,-1]
geno <- t(geno)
geno[geno==-1] <- NA
print('finished replacing NAs')

#IBS Function
ibs <- function(x,y){
  
  alleles_ibs <- 2 - abs(x-y)
  return(sum(alleles_ibs, na.rm = T)/(2*sum(!is.na(alleles_ibs))))
  
}

#Calculate IBS for each pairwise combination of isolates
d <- ncol(geno)

IBS_matrix <- matrix(nrow=d, ncol=d)

for(i in 1:(d-1)){
  for (j in (i +1):d){
    IBS_matrix[i,j] <- ibs(geno[,i], geno[,j])
  }
  print(i)
}
rownames(IBS_matrix) <- indvs
colnames(IBS_matrix) <- indvs
write.csv(IBS_matrix, "012_format/IBS_matrix6_5.csv")

#Load IBS matrix. Visualize histogram of IBS matrix results. If bimodal, select appropriate cutoff value, based on the location of the second peak. In this case, it is close to 0.99. This value is used in the next step. 
IBS_matrix <- read.csv("012_format/IBS_matrix6_5.csv", header = T)
row.names(IBS_matrix) <- IBS_matrix$X
IBS_matrix$X <- NULL
IBS_matrix <- as.matrix(IBS_matrix)
hist(IBS_matrix, breaks=100)

#Assign individuals to clonal groups. 
modify_matrix <- function(x){
  if(is.na(x) | x<.99){
    return(0)
  }else{
    
    return(1)
  }
}
clone_or_not <- structure(sapply(IBS_matrix, modify_matrix), dim=dim(IBS_matrix))

#Create network 
g <- graph_from_adjacency_matrix(clone_or_not, "undirected")
g.clusters <- clusters(graph = g)

#Construct a table of clonal group assignments and make list of cluster size corresponding to each member of network, which will be used later
cluster_sizes <- rep(NA, length(indvs))
for(i in 1:length(cluster_sizes)){
  member <- g.clusters$membership[i]
  size <- sum(g.clusters$membership == member)
  cluster_sizes[i] <- size
}

#Prepare table and variables for loop
clonal_groups <- 1:(g.clusters$no)
clone_assignments <- matrix(ncol=2)
colnames(clone_assignments) <- c("Sample", "Clonal_group")
counter <- 0

#Assign individuals to clonal groups starting with largest group
for(i in 1:length(unique(g.clusters$csize))){ #loop through all unique cluster sizes
  current_size <- sort(unique(g.clusters$csize), decreasing=T)[i] 
  same_size_clonal_groups <- unique(g.clusters$membership[cluster_sizes == current_size]) 
  for(j in 1:length(same_size_clonal_groups)){ 
    counter <- counter +1
    old_clonal_group_id <- same_size_clonal_groups[j] #Assignment to group from g.clusters$membership
    new_clonal_group_assignment <- clonal_groups[counter] #New assignment going from largest to smallest
    clone_assignments <- rbind(clone_assignments, cbind(
      indvs[which(g.clusters$membership == old_clonal_group_id)],
      new_clonal_group_assignment))
  }
}
clone_assignments <- clone_assignments[-1,]
clone_assignments <- as.data.frame(clone_assignments, stringsAsFactors = F)
clone_assignments$Clonal_group <- as.integer(clone_assignments$Clonal_group)

write.table(clone_assignments, "data/pfulvacc.txt", row.names = F, quote=F, sep="\t")

#Based on clonal group designations, retain only one isolate from each clonal lineage. Isolate with the least missing data was selected.
cleanclone = read.vcfR("data/filteredpfulva.vcf.gz")
data.set <- read.csv("data/info2.csv")
cleanclone2 <- cleanclone
cleanclone2@gt <- cleanclone@gt[, colnames(cleanclone@gt) %in% c("FORMAT", "pf76", "18009", "17038", "pf88", "17052", "19014", "18019", "19004", "17043", "18025","19006", "pf82","18010", "18012","18013", "17057","18005", "pf84")]
write.vcf(cleanclone2,file = "data/cleanclonepfulva.out.vcf.gz")
