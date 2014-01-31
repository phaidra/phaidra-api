angular.module('metadataService', [])
.factory('MetadataService', function($http) {
	
	return {
	    getObjectMetadata: function(mfv, pid) {
	         //return the promise directly.
	         return $http({
	             method  : 'GET',
	             url     : '/metadata',
	             params  : { mfv: mfv, pid: pid }
	         	//headers : are by default application/json
	         });
	    },
	
		getMetadataTree: function(mfv) {
	        return $http({
	            method  : 'GET',
	            url     : '/metadata/tree',
	            params  : { mfv: mfv }
	        });	        
	   },
		
		getLanguages: function() {
	        return $http({
	            method  : 'GET',
	            url     : '/metadata/languages'
	        });	        
	   },
	   
	   saveToObject: function(mfv, pid, metadata){
		   return $http({
			   method  : 'POST',
	           url     : '/metadata',
	           data    : { metadata: metadata, mfv: mfv, pid: pid }
		   });	        
	   },
	}
});