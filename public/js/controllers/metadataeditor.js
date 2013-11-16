
var app = angular.module('metadataeditorApp', ['ui.bootstrap']);


app.controller('MetadataeditorCtrl', function($scope) {
    
	//$scope.regex_identifier = /^o[0-9]:[0-9]+$/;
	// use: <input ng-pattern="regex_identifier" ...
	
    $scope.fields = [];
    $scope.metadata_format_version = "";
    
	//The html matches this as so and will update automatically: 
	//		<h3>Metadata Format Version: {{getMetadataFormatVersion()}}</h3>
    $scope.getMetadataFormatVersion = function() {
        return $scope.metadata_format_version;
    };
    
	//The html matches this and will update automatically: 
	//<h3>Number of fields: {{getFieldsCount()}}</h3>
    $scope.getFieldsCount = function() {
        return $scope.fields.length;
    };
    
    $scope.resetEditor = function() {
        $scope.fields = {};
        $scope.metadata_format_version = '';
    };
    
    $scope.getFromJson = function(){
    	var metadata_format_version = 1;
        $.ajax({
            type : 'GET',
            dataType : 'json',
			contentType: "application/json; charset=utf-8",
            url: '/info/metadata_format?v='+metadata_format_version,
            data: {},
			success: function(data){
				$scope.$apply(function(){ //necessary to $apply the changes
					$scope.fields = data;
					$scope.metadata_format_version = metadata_format_version;
				
				});
			},
            error : function(xhr, ajaxOptions, thrownError) {
                alert( "Error: " + xhr.responseText + "\n" + thrownError );
            }
        });
    };
    
    // used to filter array of elements: if 'hidden' is set, the field will not be included in the array
    $scope.filterHidden = function(e)
    {
        return !e.hidden;        
    };
    
    
    /*
    $scope.tabs = [
           	    { title:"Dynamic Title 1", content:"Dynamic content 1" },
           	    { title:"Dynamic Title 2", content:"Dynamic content 2", disabled: true }
           	  ];

    $scope.alertMe = function() {
           	    setTimeout(function() {
           	      alert("You've selected the alert tab!");
           	    });
           	  };

    $scope.navType = 'pills'; 
    */
});
