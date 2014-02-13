angular.module('directoryService', ['Base64'])
.factory('DirectoryService', function($http, Base64) {
	
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
	    
	    login: function(username, password) {

	         return $http({
	             method  : 'GET',
	             url     : '/login',
	             headers: {'Authorization': 'Basic ' + Base64.encode(username + ':' + password)}
	         });
	    },
	}
});