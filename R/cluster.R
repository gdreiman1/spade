# Cluster observations into ~k clusters
SPADE.cluster <- function(tbl, k) {
	if (nrow(tbl) > 60000) {
		warning("Potentially too many observations for the clustering step",immediate=TRUE);
	}

	if (nrow(tbl) < k) {
		stop("Number of requested clusters exceeds number of events")
	}

	# Transpose table before call into row major order
	cluster = Rclusterpp.hclust(tbl);
	clust = list(assgn=cutree(cluster,k=k));

	# Invalid clusters have assgn == 0
	centers = c()
	is.na(clust$assgn) <- which(clust$assgn == 0)
	for (i in c(1:max(clust$assgn, na.rm=TRUE))) {  
		obs <- which(clust$assgn == i)
		if (length(obs) >= 1) {
			centers <- rbind(centers,colMeans(tbl[obs,,drop=FALSE]))
			clust$assgn[obs] <- nrow(centers)
		} else {
			is.na(clust$assgn) <- obs
		}
	}
	return(list(centers=centers,assign=clust$assgn,hclust=cluster))
}

SPADE.clustersToMST <- function(centers, method="manhattan") {
	adjacency  <- dist(centers, method=method)
	full_graph <- graph.adjacency(as.matrix(adjacency),mode="undirected",weighted=TRUE)
	mst_graph  <- minimum.spanning.tree(full_graph)
	mst_graph
}

SPADE.writeGraph <- function(graph, outfilename) {
	 write.graph(graph, outfilename, format="gml")
}

SPADE.FCSToTree <- function(
	infilenames, 
	outfilename, 
	graphfilename,
	clusterfilename, 
	cols=NULL, 
	k=200, 
	arcsinh_cofactor=NULL,
	transforms=flowCore::arcsinhTransform(a=0, b=0.2),
	desired_samples=50000,
	comp=TRUE
) {
  
	if (!is.null(arcsinh_cofactor)) {
		warning("arcsinh_cofactor is deprecated, use transform=flowCore::arcsinhTransform(...) instead")
		transforms <- flowCore::arcsinhTransform(a=0, b=1/arcsinh_cofactor)
	}

	data = c()
	for (f in infilenames) {
		# Load in FCS file
		in_fcs  <- SPADE.read.FCS(f, comp=comp);
		in_data <- exprs(in_fcs);
	
		params <- parameters(in_fcs);
		pd     <- pData(params);
	
		# Select out the desired columns
		if (is.null(cols)) { 
			cols <- as.vector(pd$name) 
		}
		idxs <- match(cols,pd$name)
			if (any(is.na(idxs))) { 
				stop("Invalid column specifier") 
			}
	
		data <- rbind(data,in_data[,idxs,drop=FALSE])
			colnames(data) <- pd$name[idxs]
	}
	
	# Downsample data if neccessary 
	if (nrow(data) > desired_samples) {
		data <- data[sample(1:nrow(data),desired_samples),]
	} else if (nrow(data) == 0) {
		stop("Number of observations to cluster is zero. Did the density/downsampling warn about data similarity?")
	}
	
	# Compute the cluster centers, marking any single observation clusters as NA
	clust <- SPADE.cluster(SPADE.transform.matrix(data, transforms), k);
	
	# Generate path for merge order
	mergeOrderPath = paste(dirname(outfilename),"/","merge_order.txt",sep="");

	# Write the DEFAULT merge order
	write.table(clust$hclust$merge,file=mergeOrderPath,sep="\t",quote=F,row.names=F,col.names=F)
	
	# Write out FCS file downsampled data used in clustering, along with assignment
	# Strip out observations in single observation clusters
	ff <- SPADE.build.flowFrame(subset(cbind(data, cluster=clust$assign),!is.na(clust$assign)))
	write.FCS(ff, outfilename) 
	
	# Write out the MST and cluster centers to specified files ignoring single observation clusters
	SPADE.writeGraph(SPADE.clustersToMST(clust$centers),graphfilename);
	write.table(clust$centers,file=clusterfilename,row.names=FALSE,col.names=colnames(data))
}
 
