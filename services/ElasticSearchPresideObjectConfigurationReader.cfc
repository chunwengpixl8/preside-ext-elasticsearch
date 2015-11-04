component output=false singleton=true {

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
	public array function listIndexes() output=false {
		return _simpleLocalCache( "listIndexes", function(){
			var indexes = {};
			var objects = listSearchEnabledObjects();

			for( var object in objects ){
				var conf = getObjectConfiguration( object );
				if ( Len( Trim( conf.indexName ?: "" ) ) ) {
					indexes[ conf.indexName ] = true;
				}
			}

			return indexes.keyArray();
		} );
	}

	public array function listDocumentTypes( required string indexName ) output=false {
		var args = arguments;

		return _simpleLocalCache( "listDocumentTypes" & args.indexName, function(){
			var docTypes = {};
			var objects = listSearchEnabledObjects();

			for( var object in objects ){
				var conf = getObjectConfiguration( object );
				if ( ( conf.indexName ?: "" ) == args.indexName && Len( Trim( conf.documentType ?: "" ) ) ) {
					docTypes[ conf.documentType ] = true;
				}
			}

			return docTypes.keyArray();
		} );
	}

	public struct function getFields( required string indexName, required string documentType ) output=false {
		var args = arguments;

		return _simpleLocalCache( "listFieldsForDocumentType" & args.indexName & args.documentType, function(){
			var fields  = {};
			var objects = listSearchEnabledObjects();
			var conf    = {};
			var field   = "";

			for( var object in objects ){

				conf = getObjectConfiguration( object );
				if ( ( conf.indexName ?: "" ) == args.indexName && ( conf.documentType ?: "" ) == args.documentType ) {

					if ( _isPageType( object ) ) {
						var pageConf = getObjectConfiguration( "page" );

						for( field in pageConf.fields ){
							fields[ field ] = getFieldConfiguration( "page", field );
						}
					} else if ( _isAssetObject( object ) ) {
						var assetConf = getObjectConfiguration( "asset" );

						for( field in assetConf.fields ){
							fields[ field ] = getFieldConfiguration( "asset", field );
						}
					}

					for( field in conf.fields ){
						fields[ field ] = getFieldConfiguration( object, field );
					}
				}
			}

			return fields;
		} );
	}

	public array function listSearchEnabledObjects() output=false {
		return _simpleLocalCache( "listSearchEnabledObjects", function(){
			var poService = _getPresideObjectService();

			return poService.listObjects().filter( function( objectName ){
				var isPageType       = _isPageType( objectName );
				var isAssetObject    = _isAssetObject( objectName );
				var isSystemPageType = isPageType && poService.getObjectAttribute( objectName, "isSystemPageType", false );
				var searchEnabled    = objectName != "page" && poService.getObjectAttribute( objectName, "searchEnabled", ( isPageType && !isSystemPageType ) );

				searchEnabled = searchEnabled || isAssetObject;

				return IsBoolean( searchEnabled ) && searchEnabled;
			} );

		} );
	}

	public struct function getObjectConfiguration( required string objectName ) output=false {
		var args = arguments;

		return _simpleLocalCache( "getObjectConfiguration" & args.objectName, function(){
			var poService     = _getPresideObjectService();
			var configuration = {};

			configuration.indexName        = poService.getObjectAttribute( args.objectName, "searchIndex" );
			configuration.documentType     = poService.getObjectAttribute( args.objectName, "searchDocumentType" );
			configuration.indexFilters     = ListToArray( poService.getObjectAttribute( args.objectName, "searchIndexFilters" ) );
			configuration.hasOwnDataGetter = doesObjectHaveDataGetterMethod( args.objectName );
			configuration.fields           = [];

			if ( !Len( Trim( configuration.indexName ) ) ) {
				configuration.indexName = _getDefaultIndexName();
			}
			if ( !Len( Trim( configuration.documentType ) ) ) {
				configuration.documentType = args.objectName;
			}

			var props = poService.getObjectProperties( args.objectName );
			for( var propName in props ){
				var prop          = props[ propName ];
				var searchEnabled = prop.searchEnabled ?: "";

				if ( IsBoolean( searchEnabled ) && searchEnabled ){
					configuration.fields.append( propName );
				}
			}
			if ( !configuration.fields.find( "id" ) ) {
				configuration.fields.append( "id" );
			}

			if ( !configuration.indexFilters.len() && _isPageType( args.objectName ) ) {
				configuration.indexFilters = [ "elasticSearchPageFilter", "livePages" ];
			}
			if ( !configuration.indexFilters.len() && _isAssetObject( args.objectName ) ) {
				configuration.indexFilters = [ "elasticSearchAssetFilter" ];
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

			configuration.fieldName  = poService.getObjectPropertyAttribute( args.objectName, args.fieldName, "searchField", args.fieldName );
			configuration.searchable = false;
			configuration.sortable   = poService.getObjectPropertyAttribute( args.objectName, args.fieldName, "searchSortable" );
			configuration.sortable   = IsBoolean( configuration.sortable ) && configuration.sortable;
			configuration.type       = poService.getObjectPropertyAttribute( args.objectName, args.fieldName, "searchType", "" );

			if ( !Len( Trim( configuration.type ?: "" ) ) ) {
				switch( fieldType ){
					case "string":
					case "date":
					case "boolean":
						configuration.type = fieldType;
					break;

					case "numeric":
						var dbtype = poService.getObjectPropertyAttribute( args.objectName, args.fieldName, "dbtype", "" );

						switch( dbType ) {
							case "bigint signed":
							case "int unsigned":
							case "bigint":
								configuration.type = "long";
							break;

							case "float":
							case "decimal":
								configuration.type = "float";
							break;

							case "double":
							case "double precision":
							case "real":
								configuration.type = "double";
							break;

							default:
								configuration.type = "integer";
						}
					break;

					default:
						configuration.type = "string";
				}
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

	public boolean function doesObjectHaveDataGetterMethod( required string objectName ) output=false {
		var args = arguments;

		return _simpleLocalCache( "doesObjectHaveDataGetterMethod" & args.objectName, function(){
			var object = _getPresideObjectService().getObject( args.objectName );

			return IsValid( "function", object.getDataForSearchEngine ?: "" );
		} );
	}

	public array function listObjectsForIndex( required string indexName ) output=false {
		var args = arguments;

		return _simpleLocalCache( "listObjectsForIndex" & args.indexName, function(){
			return listSearchEnabledObjects().filter( function( objName ){
				var objConfig = getObjectConfiguration( objName );

				return ( objConfig.indexName ?: "" ) == args.indexName;
			} );
		} );
	}

	public boolean function isObjectSearchEnabled( required string objectName ) output=false {
		var args = arguments;

		return _simpleLocalCache( "isObjectSearchEnabled" & args.objectName, function(){
			return listSearchEnabledObjects().findNoCase( args.objectName );
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

	private boolean function _isPageType( required string objectName ) output=false {
		var isPageType = _getPresideObjectService().getObjectAttribute( arguments.objectName, "isPageType", false );

		return IsBoolean( isPageType ) && isPageType;
	}

	private boolean function _isAssetObject( required string objectName ) output=false {
		return arguments.objectName == "asset";
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