angular.module('directoryService', [])
.factory('DirectoryService', function($http) {
	
	return {
	    getOrgUnits: function(parent_id) {
	         //return the promise directly.
	         return $http({
	             method  : 'GET',
	             url     : '/directory/get_org_units',
	             params  : { parent_id: parent_id }
	         	//headers : are by default application/json
	         });
	    },
	
	}
});