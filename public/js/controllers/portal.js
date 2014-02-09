var app = angular.module('portalApp', ['ui.bootstrap', 'ajoslin.promise-tracker', 'directoryService']);

var ModalInstanceCtrl = function ($scope, $modalInstance) {

	  $scope.ok = function () {
	    $modalInstance.close();
	  };

	  $scope.cancel = function () {
	    $modalInstance.dismiss('cancel');
	  };
};

app.controller('PortalCtrl', function($scope, $modal, $log, DirectoryService, promiseTracker) {
    
	// we will use this to track running ajax requests to show spinner
	$scope.loadingTracker = promiseTracker.register('loadingTracker');
	
    $scope.alerts = [];        
    
    $scope.closeAlert = function(index) {
    	$scope.alerts.splice(index, 1);
    };
    $scope.init = function () {
    	//$scope.apply();
    };
    
    $scope.signin_open = function () {

        var modalInstance = $modal.open({
          templateUrl: '/views/partials/signin.html',        	
          controller: ModalInstanceCtrl
        });

        modalInstance.result.then(function () {
        	
        }, function () {
          $log.info('Modal dismissed at: ' + new Date());
        });
      };
});



