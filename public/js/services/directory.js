angular.module('directoryService', [])
.factory('DirectoryService', function($http) {
	
	return {
	    getOrgUnits: function(parent_id, namespace) {
	         //return the promise directly.
	         return $http({
	             method  : 'GET',
	             url     : '/directory/get_org_units',
	             params  : { parent_id: parent_id, namespace: namespace }
	         	//headers : are by default application/json
	         });
	    },
	
	    getStudyPlans: function() {
	         return $http({
	             method  : 'GET',
	             url     : '/directory/get_study_plans',
	         });
	    },
	    
	    getStudy: function(splid, ids, level) {
	         return $http({
	             method  : 'GET',
	             url     : '/directory/get_study',
	             params  : { splid: splid, ids: ids, level: level }
	         });
	    },
	}
});