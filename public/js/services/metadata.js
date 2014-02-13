angular.module('metadataService', [])
.factory('MetadataService', function($http) {
	
	return {
		getUwmetadataFromObject: function(mfv, pid) {
	         //return the promise directly.
	         return $http({
	             method  : 'GET',
	             url     : '/object/'+pid+'/uwmetadata',
	             params  : { mfv: mfv }
	         	//headers : are by default application/json
	         });
	    },
	
		getUwmetadataTree: function(mfv) {
	        return $http({
	            method  : 'GET',
	            url     : '/uwmetadata/tree',
	            params  : { mfv: mfv }
	        });	        
	   },
		
		getLanguages: function() {
	        return $http({
	            method  : 'GET',
	            url     : '/metadata/languages'
	        });	        
	   },
	   
	   saveUwmetadataToObject: function(mfv, pid, uwmetadata){
		   return $http({
			   method  : 'POST',
	           url     : '/object/'+pid+'/uwmetadata',
	           data    : { uwmetadata: uwmetadata, mfv: mfv }
		   });	        
	   },
	}
});