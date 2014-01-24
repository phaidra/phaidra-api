var app = angular.module('metadataeditorApp', ['ui.bootstrap']);


app.controller('MetadataeditorCtrl', function($scope) {
    
	$scope.regex_pid = /^[a-op-zA-Z]+:[0-9]+$/;
	// use: <input ng-pattern="regex_identifier" ...
	
    $scope.fields = [];
    $scope.languages = [];
    $scope.metadata_format_version = "";
    $scope.pid = '';
    
    $scope.getMetadataFormatVersion = function() {
        return $scope.metadata_format_version;
    };
    	
    $scope.getFieldsCount = function() {
        return $scope.fields.length;
    };
    
    $scope.init = function () {
    	//alert('klkl');
    	
    	$.ajax({
            type : 'GET',
            dataType : 'json',
			contentType: "application/json; charset=utf-8",
            url: '/info/languages',
            data: {},
			success: function(data){				
				$scope.$apply(function(){
					$scope.languages = data;				
				});
			},
            error : function(xhr, ajaxOptions, thrownError) {
                alert( "Error: " + xhr.responseText + "\n" + thrownError );
            }
        });
        
    };
    
    //$scope.resetEditor = function() {
    //    $scope.fields = {};
    //    $scope.metadata_format_version = '';
    //};
    
    $scope.getFromJson = function(){
    	var metadata_format_version = 1;
        $.ajax({
            type : 'GET',
            dataType : 'json',
			contentType: "application/json; charset=utf-8",
            url: '/info/metadata_format?mfv='+metadata_format_version,
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
    
    $scope.loadObject = function(pid){
    	var metadata_format_version = 1;
        $.ajax({
            type : 'GET',
            dataType : 'json',
			contentType: "application/json; charset=utf-8",
            url: '/get/metadata?mfv='+metadata_format_version+'&pid='+escape(pid),
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
    
    // returns 
    // -1 - if we are 
    // 0 - if we cannot delete and cannot add
    // 1 - if we cannot add
    $scope.canDelete = function(child){
    	var a = $scope.getContainingArray(this);  
    	var cnt = 0;
    	for (i = 0; i < a.length; ++i) {
    		if(a[i].xmlns == child.xmlns && a[i].xmlname == child.xmlname){
    			cnt++;
    		}
    	}
    	return cnt > 1;
    }
    
    $scope.addNewElement = function(child){    	    	
    	// array of elements to which we are going to insert
    	var arr = $scope.getContainingArray(this);    	
    	// copy the element
    	var tobesistr = angular.copy(child);    	
    	// get index of the current element in this array
    	var idx = angular.element.inArray(child, arr); // we loaded jQuery before angular so angular.element should equal jQuery
    	// insert into array at specified index, angular will sort the rest out
    	arr.splice(idx, 0, tobesistr);    
    }
    
    $scope.deleteElement = function(child){    	
    	// array of elements where we are going to delete
    	var arr = $scope.getContainingArray(this);	    	    	
    	// get index of the current element in this array
    	var idx = angular.element.inArray(child, arr); // we loaded jQuery before angular so angular.element should equal jQuery
    	// insert into array at specified index, angular will sort the rest out
    	arr.splice(idx, 1);    
    }
    
    // black magic here...
    $scope.getContainingArray = function(scope){
    	// this works for normal fields
    	var arr = scope.$parent.$parent.$parent.field.children;    	
    	// this for blocks
    	if(scope.$parent.$parent.$parent.$parent.$parent.child){
    		if(scope.$parent.$parent.$parent.$parent.$parent.child.children){
    			arr = scope.$parent.$parent.$parent.$parent.$parent.child.children;
    		}
    	}    	
    	// and this for fields in blocks
    	if(scope.$parent.$parent.$parent.$parent.$parent.$parent.child){
    		if(scope.$parent.$parent.$parent.$parent.$parent.$parent.child.children){
    			arr = scope.$parent.$parent.$parent.$parent.$parent.$parent.child.children;
    		}
    	}
    	return arr;
    }
    
    Array.prototype.move = function(from, to) {
        this.splice(to, 0, this.splice(from, 1)[0]);
    };
    
    $scope.upElement = function(child){
    	// array of elements which we are going to rearrange
    	var arr = $scope.getContainingArray(this);
    	// get index of the current element in this array
    	var idx = angular.element.inArray(child, arr);
    	
    	// update the data_order property
    	child.data_order--;
    	arr[idx-1].data_order++;
    	
    	// move to index--
    	if(idx > 0){
    		arr.move(idx, idx-1);
    	}    	
    }
    
    $scope.canUpElement = function(child){
    	// array of elements which we are going to rearrange
    	var arr = $scope.getContainingArray(this);
    	// get index of the current element in this array
    	var idx = angular.element.inArray(child, arr);

    	return idx > 0;
    }
    
    
    $scope.downElement = function(child){
    	// array of elements which we are going to rearrange
    	var arr = $scope.getContainingArray(this);
    	// get index of the current element in this array
    	var idx = angular.element.inArray(child, arr);
    	
    	// update the data_order property
    	child.data_order++;
    	arr[idx+1].data_order--;
    	
    	// move to index++
    	arr.move(idx, idx+1);    	
    }
    
    $scope.canDownElement = function(child){
    	// array of elements which we are going to rearrange
    	var arr = $scope.getContainingArray(this);
    	// get index of the current element in this array
    	var idx = angular.element.inArray(child, arr);

    	return idx < (arr.length-1);
    }
    
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
    
    /*
    $scope.$on('$viewContentLoaded', function() {
    	
    	
    	
    	$.ajax({
            type : 'GET',
            dataType : 'json',
			contentType: "application/json; charset=utf-8",
            url: '/info/languages',
            data: {},
			success: function(data){
				//alert('klkl');
				$scope.$apply(function(){
					$scope.languages = data;				
				});
			},
            error : function(xhr, ajaxOptions, thrownError) {
                alert( "Error: " + xhr.responseText + "\n" + thrownError );
            }
        });
    	
        
    });
    */
        
    
    //$scope.setLanguage
});

