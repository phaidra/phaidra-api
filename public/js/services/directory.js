angular.module('directoryService', [])
.factory('DirectoryService', function($http) {
	
	return {
	    getOrgUnits: function(parent_id, values_namespace) {
	         //return the promise directly.
	         return $http({
	             method  : 'GET',
	             url     : '/directory/get_org_units',
	             params  : { parent_id: parent_id, values_namespace: values_namespace }
	         	//headers : are by default application/json
	         });
	    },
	
	    getStudyPlans: function() {
	         return $http({
	             method  : 'GET',
	             url     : '/directory/get_study_plans',
	         });
	    },
	    
	    getStudy: function(spl, ids, values_namespace) {
	         return $http({
	             method  : 'GET',
	             url     : '/directory/get_study',
	             params  : { spl: spl, ids: ids, values_namespace: values_namespace }
	         });
	    },
	    
	    getStudyName: function(spl, ids) {
	         return $http({
	             method  : 'GET',
	             url     : '/directory/get_study_name',
	             params  : { spl: spl, ids: ids }
	         });
	    },
	}
});