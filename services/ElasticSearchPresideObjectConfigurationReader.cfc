component output=false {

// CONSTRUCTOR
	/**
	 * @presideObjectService.inject       presideObjectService
	 * @systemConfigurationService.inject systemConfigurationService
	 *
	 */
	public any function init( required any presideObjectService, required any systemConfigurationService ) output=false {
		_setLocalCache( {} );
		_setPresideObjectService( arguments.presideObjectService );
		_setSystemConfigurationService( arguments.systemConfigurationService );

		return this;
	}

// PUBLIC API METHODS
	public array function listSearchEnabledObjects() output=false {
		return _simpleLocalCache( "listSearchEnabledObjects", function(){
			var poService = _getPresideObjectService();

			return poService.listObjects().filter( function( objectName ){
				var searchEnabled = objectName != "page" && poService.getObjectAttribute( objectName, "searchEnabled", false );

				return IsBoolean( searchEnabled ) && searchEnabled;
			} );

		} );
	}

	public struct function getObjectConfiguration( required string objectName ) output=false {
		var args = arguments;

		return _simpleLocalCache( "getObjectConfiguration" & args.objectName, function(){
			var poService     = _getPresideObjectService();
			var configuration = {};

			configuration.indexName    = poService.getObjectAttribute( args.objectName, "searchIndex" );
			configuration.documentType = poService.getObjectAttribute( args.objectName, "searchDocumentType" );
			configuration.fields       = [];

			if ( !Len( Trim( configuration.indexName ) ) ) {
				configuration.indexName = _getDefaultIndexName();
			}
			if ( !Len( Trim( configuration.documentType ) ) ) {
				configuration.documentType = args.objectName;
			}

			for( var prop in poService.getObjectProperties( args.objectName ) ){
				var searchEnabled = poService.getObjectPropertyAttribute( args.objectName, prop.getAttribute( "name" ), "searchEnabled" );

				if ( IsBoolean( searchEnabled ) && searchEnabled ){
					configuration.fields.append( prop.getAttribute( "name" ) );
				}
			}
			if ( !configuration.fields.find( "id" ) ) {
				configuration.fields.append( "id" );
			}

			return configuration;
		} );
	}

	public struct function getFieldConfiguration( required string objectName, required string fieldName ) output=false {
		var args = arguments;

		return _simpleLocalCache( "getFieldConfiguration" & args.objectName & args.fieldname, function(){
			var poService     = _getPresideObjectService();
			var configuration = {};
			var fieldType     = poService.getObjectPropertyAttribute( args.objectName, args.fieldName, "type" );

			configuration.searchable = false;
			configuration.sortable = poService.getObjectPropertyAttribute( args.objectName, args.fieldName, "searchSortable" );
			configuration.sortable = IsBoolean( configuration.sortable ) && configuration.sortable;

			switch( fieldType ){
				case "numeric":
					configuration.type = "number";
				break;
				case "string":
				case "date":
				case "boolean":
					configuration.type = fieldType;
				break;
				default:
					configuration.type = "string";
			}

			switch( configuration.type ){
				case "string":
					configuration.searchable = poService.getObjectPropertyAttribute( args.objectName, args.fieldName, "searchSearchable" );
					if ( !Len( Trim( configuration.searchable ) ) ) {
						configuration.searchable = true;
					} else {
						configuration.searchable = IsBoolean( configuration.searchable ) && configuration.searchable;
					}

					configuration.analyzer = poService.getObjectPropertyAttribute( args.objectName, args.fieldName, "searchAnalyzer" );
					if ( !Len( Trim( configuration.analyzer ) ) ) {
						configuration.analyzer = "default";
					}
				break;

				case "date":
					configuration.dateFormat = poService.getObjectPropertyAttribute( args.objectName, args.fieldName, "searchDateFormat" );
					configuration.ignoreMalformedDates = poService.getObjectPropertyAttribute( args.objectName, args.fieldName, "searchIgnoreMalformed" );

					if ( !Len( Trim( configuration.dateFormat ) ) ) {
						configuration.delete( "dateFormat" );
					}
					if ( !Len( Trim( configuration.ignoreMalformedDates ) ) ) {
						configuration.ignoreMalformedDates = true;
					} else {
						configuration.ignoreMalformedDates = IsBoolean( configuration.ignoreMalformedDates ) && configuration.ignoreMalformedDates;
					}
				break;
			}

			return configuration;
		} );
	}

// PRIVATE HELPERS
	private any function _simpleLocalCache( required string cacheKey, required any generator ) output=false {
		var cache = _getLocalCache();

		if ( !cache.keyExists( cacheKey ) ) {
			cache[ cacheKey ] = generator();
		}

		return cache[ cacheKey ] ?: NullValue();
	}


// GETTERS AND SETTERS
	private any function _getPresideObjectService() output=false {
		return _presideObjectService;
	}
	private void function _setPresideObjectService( required any presideObjectService ) output=false {
		_presideObjectService = arguments.presideObjectService;
	}

	private any function _getSystemConfigurationService() output=false {
		return _systemConfigurationService;
	}
	private void function _setSystemConfigurationService( required any systemConfigurationService ) output=false {
		_systemConfigurationService = arguments.systemConfigurationService;
	}

	private struct function _getLocalCache() output=false {
		return _localCache;
	}
	private void function _setLocalCache( required struct localCache ) output=false {
		_localCache = arguments.localCache;
	}

	private any function _getDefaultIndexName() output=false {
		return _getSystemConfigurationService().getSetting( "elasticsearch", "default_index" );
	}

}