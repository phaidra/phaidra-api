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
    	// increment order of the new element (we are appending to the current one)
    	// and also all the next elements
    	// but only if the elements are actually ordered
    	if(child.ordered){
    		tobesistr.data_order++;
    		var i;
        	for (i = idx+1; i < arr.length; ++i) {
        		// update only elements of the same type
        		if(arr[i].xmlns == child.xmlns && arr[i].xmlname == child.xmlname){
        			arr[i].data_order++;
        		}
        	}
    	}    	
    	// insert into array at specified index, angular will sort the rest out
    	arr.splice(idx+1, 0, tobesistr);    
    }
    
    $scope.deleteElement = function(child){    	
    	// array of elements where we are going to delete
    	var arr = $scope.getContainingArray(this);	    	    	
    	// get index of the current element in this array
    	var idx = angular.element.inArray(child, arr); // we loaded jQuery before angular so angular.element should equal jQuery
    	// decrement data_order of remaining elements
    	if(child.ordered){
	    	var i;
	    	for (i = idx+1; i < arr.length; ++i) {
	    		// update only elements of the same type
        		if(arr[i].xmlns == child.xmlns && arr[i].xmlname == child.xmlname){
        			arr[i].data_order--;
        		}
	    	}
    	}
    	// delete
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
    	if(child.ordered){
	    	child.data_order--;
	    	// only if it's the same type (should be always true
	    	// because we are checking this in canUpElement)
    		if(arr[idx-1].xmlns == child.xmlns && arr[idx-1].xmlname == child.xmlname){
    			arr[idx-1].data_order++;
    		}
    	}
    	
    	// move to index--
    	if(idx > 0){
    		arr.move(idx, idx-1);
    	}    	
    }

    $scope.downElement = function(child){
    	// array of elements which we are going to rearrange
    	var arr = $scope.getContainingArray(this);
    	// get index of the current element in this array
    	var idx = angular.element.inArray(child, arr);
    	
    	// update the data_order property
    	if(child.ordered){
	    	child.data_order++;
	    	// only if it's the same type (should be always true
	    	// because we are checking this in canDownElement)
    		if(arr[idx+1].xmlns == child.xmlns && arr[idx+1].xmlname == child.xmlname){
    			arr[idx+1].data_order--;
    		}
    	}
    	
    	// move to index++
    	arr.move(idx, idx+1);    	
    }
    
    $scope.canUpElement = function(child){
    	return child.ordered && (child.data_order > 0);
    }

    $scope.canDownElement = function(child){
    	
    	if(!child.ordered){ return false; }
    	
    	// this array can contain also another type of elements
    	// but we only order the same type, so find if there is
    	// an element of the same type with higher data_ordered
    	var arr = $scope.getContainingArray(this);
    	
	    var i;
	    for (i = 0; i < arr.length; ++i) {
	        if(arr[i].data_order > child.data_order){
	        	return true;
	        }
	    }
    	
	    return false;

    }
    
    // just for debug
    $scope.getIndex = function(child){
    	// array of elements which we are going to rearrange
    	var arr = $scope.getContainingArray(this);
    	// get index of the current element in this array
    	return angular.element.inArray(child, arr);
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

