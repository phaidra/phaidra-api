
// Apply any event handlers
app.directive( "helptooltip", function(){
    return {
            restrict: "A", // look for an attribute 'helptext'
            link: function(scope, element, attr){
            element.click(function(){
                alert( $(this).closest('p').html() ); //the help text
                return false;
            });
        }
    };
});